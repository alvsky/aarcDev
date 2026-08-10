-- § B15 + D1: nepročitano i primatelji pusha prestaju ovisiti o project_members.
--
-- B15: sve tri putanje (fetchUnread, get_unread_total, popis primatelja pusha)
-- vozile su iz project_members INNER JOINom. Radilo je samo zato što postojeći
-- projekti imaju te retke od prije organizacija. Prvi projekt vidljiv
-- organizaciji, a bez izričitih članova, tiho bi ostao bez badgea i pusha.
--
-- D1: brojanje se seli u bazu. Klijent je dosad dohvaćao SVE poruke svih svojih
-- projekata da bi ih prebrojao; sada dobiva nekoliko desetaka gotovih redaka.
--
-- project_members od sada služi SAMO kao izvor osobnih postavki, i to preko
-- LEFT JOINa — nepostojanje retka znači "zadano uključeno", ne "bez pristupa".

-- ---------------------------------------------------------------------------
-- 1) Pravilo pristupa za PROIZVOLJNOG korisnika.
--
-- Push mora znati smije li NETKO DRUGI vidjeti projekt, a jednoargumentna
-- verzija je vezana na auth.uid(). Umjesto duplikata, jezgra prima korisnika, a
-- postojeći potpis postaje omotač — pravilo ostaje na jednom mjestu.
-- ---------------------------------------------------------------------------
create or replace function public.can_access_project(pid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = uid
    where p.id = pid
      and (
        (p.visibility = 'org' and om.role <> 'guest')
        or om.role in ('owner', 'admin')
        or exists (
          select 1 from project_members pm
          where pm.project_id = p.id and pm.user_id = uid
        )
      )
  )
$$;

create or replace function public.can_access_project(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_project(pid, auth.uid())
$$;

-- ---------------------------------------------------------------------------
-- 2) Pravilo "jedna stavka, jedan badge" seli iz JS-a u SQL.
--
-- Dvije funkcije jer se pravila NAMJERNO razlikuju (docs/item-model.md):
-- nova stavka u završnoj fazi ne broji se nigdje, ali nepročitana PORUKA na
-- zatvorenoj stavci je stvaran signal i pripisuje se kartici u kojoj se ta
-- stavka može pronaći.
-- ---------------------------------------------------------------------------
create or replace function public.item_tab_new(p_kind text, p_stage text)
returns text
language sql
immutable
as $$
  select case
    when p_stage in ('accepted', 'in_progress', 'testing') then 'tbi'
    when p_stage in ('done', 'rejected')                   then null
    when p_kind = 'bug'                                    then 'bugs'
    when p_kind = 'idea'                                   then 'ideas'
    else null   -- zadatak izvan aktivnog rada nema svoju karticu
  end
$$;

create or replace function public.item_tab_thread(p_kind text, p_stage text)
returns text
language sql
immutable
as $$
  select case
    when p_stage in ('accepted', 'in_progress', 'testing') then 'tbi'
    when p_kind = 'bug'                                    then 'bugs'
    when p_kind = 'idea'                                   then 'ideas'
    else 'tbi'
  end
$$;

-- ---------------------------------------------------------------------------
-- 3) Jezgra: nepročitano za zadanog korisnika, u ravnim recima.
--
-- scope='channel' → ref je naziv kanala
-- scope='thread'  → ref je id stavke, tab kaže gdje se zbraja
-- scope='item'    → nove stavke, ref prazan, tab je kartica
--
-- Zbroj svih n je ukupan broj za značku. Kartica = svoje 'item' + svoje 'thread'.
--
-- PROMJENA PONAŠANJA: prije su nepročitane poruke ulazile u ukupan zbroj čak i
-- kad je kategorija bila isključena, ali se nisu zbrajale u karticu — pa ukupno
-- nije bilo jednako zbroju kartica. Sada notif_messages odlučuje broje li se
-- poruke uopće, a kad se broje, uvijek idu i u svoju karticu.
-- ---------------------------------------------------------------------------
create or replace function public._unread_rows(p_user uuid)
returns table (project_id uuid, scope text, ref text, tab text, n integer)
language sql
stable
security definer
set search_path = public
as $$
  with prefs as (
    select p.id as project_id,
           coalesce(pm.notif_messages, true) as notif_messages,
           coalesce(pm.notif_ideas, true)    as notif_ideas,
           coalesce(pm.notif_bugs, true)     as notif_bugs,
           coalesce(pm.notif_tbi, true)      as notif_tbi
      from projects p
      join org_members om on om.org_id = p.org_id and om.user_id = p_user
      -- LEFT: nema retka = zadane postavke, a NE izostanak pristupa (B15)
      left join project_members pm
        on pm.project_id = p.id and pm.user_id = p_user
     where public.can_access_project(p.id, p_user)
       and coalesce(pm.badge_enabled, true)
  ),
  msgs as (
    select m.project_id, m.item_id, m.channel, count(*)::int as n
      from messages m
      join prefs pr on pr.project_id = m.project_id and pr.notif_messages
     where m.author_id is distinct from p_user
       and not exists (
         select 1 from message_reads r
          where r.user_id = p_user
            and r.project_id = m.project_id
            and r.item_id is not distinct from m.item_id
            and r.channel  is not distinct from m.channel
            and r.last_read_at >= m.created_at
       )
     group by m.project_id, m.item_id, m.channel
  ),
  new_items as (
    select i.project_id,
           public.item_tab_new(i.kind, i.stage) as tab,
           count(*)::int as n
      from items i
      join prefs pr on pr.project_id = i.project_id
     where i.created_by is distinct from p_user
       and public.item_tab_new(i.kind, i.stage) is not null
       and case public.item_tab_new(i.kind, i.stage)
             when 'ideas' then pr.notif_ideas
             when 'bugs'  then pr.notif_bugs
             when 'tbi'   then pr.notif_tbi
             else false
           end
       and not exists (
         select 1 from item_user_state s
          where s.user_id = p_user and s.item_id = i.id and s.read_at is not null
       )
     group by i.project_id, public.item_tab_new(i.kind, i.stage)
  )
  select project_id, 'channel'::text, coalesce(channel, 'main'), null::text, n
    from msgs where item_id is null
  union all
  select m.project_id, 'thread'::text, m.item_id::text,
         public.item_tab_thread(i.kind, i.stage), m.n
    from msgs m join items i on i.id = m.item_id
   where m.item_id is not null
  union all
  select project_id, 'item'::text, ''::text, tab, n
    from new_items
$$;

-- Javna inačica: uvijek za pozivatelja, bez parametra koji bi se dao podmetnuti.
create or replace function public.get_unread()
returns table (project_id uuid, scope text, ref text, tab text, n integer)
language sql
stable
security definer
set search_path = public
as $$
  select * from public._unread_rows(auth.uid())
$$;

-- ---------------------------------------------------------------------------
-- 4) get_unread_total — koristi ga edge funkcija za broj na značci pusha.
-- Prepisan na istu jezgru, pa nestaje i njegov INNER JOIN problem.
-- ---------------------------------------------------------------------------
create or replace function public.get_unread_total(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(n), 0)::int from public._unread_rows(p_user_id)
$$;

-- ---------------------------------------------------------------------------
-- 5) Primatelji pusha — ista pravila pristupa i iste postavke.
-- ---------------------------------------------------------------------------
create or replace function public.push_recipients(
  p_project uuid,
  p_exclude uuid,
  p_field   text
)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select om.user_id
    from projects p
    join org_members om on om.org_id = p.org_id
    left join project_members pm
      on pm.project_id = p.id and pm.user_id = om.user_id
   where p.id = p_project
     and om.user_id is distinct from p_exclude
     and public.can_access_project(p.id, om.user_id)
     and coalesce(pm.badge_enabled, true)
     and case p_field
           when 'notif_messages' then coalesce(pm.notif_messages, true)
           when 'notif_ideas'    then coalesce(pm.notif_ideas, true)
           when 'notif_bugs'     then coalesce(pm.notif_bugs, true)
           when 'notif_tbi'      then coalesce(pm.notif_tbi, true)
           else true
         end
$$;

-- ---------------------------------------------------------------------------
-- 6) Prava izvršavanja (zatvara i B14)
--
-- Funkcije koje primaju TUĐI korisnički id smiju biti dostupne samo poslužitelju.
-- get_unread_total je dosad bio pozivljiv iz preglednika s bilo čijim id-em.
-- ---------------------------------------------------------------------------
revoke all on function public._unread_rows(uuid)                  from public, anon, authenticated;
revoke all on function public.get_unread_total(uuid)              from public, anon, authenticated;
revoke all on function public.push_recipients(uuid, uuid, text)   from public, anon, authenticated;
revoke all on function public.can_access_project(uuid, uuid)      from public, anon, authenticated;
revoke all on function public.get_unread()                        from public, anon;

grant execute on function public._unread_rows(uuid)                to service_role;
grant execute on function public.get_unread_total(uuid)            to service_role;
grant execute on function public.push_recipients(uuid, uuid, text) to service_role;
grant execute on function public.can_access_project(uuid, uuid)    to service_role;
grant execute on function public.get_unread()                      to authenticated;
