-- project_members postaje "pratim ovaj projekt", ne dozvola za pristup.
--
-- Otkad je can_access_project (B7) postao jedina točka odlučivanja o PRISTUPU,
-- project_members je ostao živjeti kao izvor osobnih postavki (badge_enabled,
-- notif_*). Posljedica koju je uočio korisnik: svaki član organizacije dobiva
-- obavijesti za SVAKI projekt vidljiv organizaciji, uključujući one koje nikad
-- nije otvorio — spam po difoltu, ne po izboru.
--
-- Rješenje: project_members redak = pretplata. Bez retka i dalje vidiš i
-- otvaraš projekt (can_access_project to ne dira), ali te ne zvoni.
--
-- ⚠️ Ovime se _unread_rows i push_recipients vraćaju s LEFT JOIN na INNER JOIN
-- na project_members. To IZGLEDA kao poništavanje B15, ali nije: B15 je bio
-- problem jer se project_members koristio kao provjera PRISTUPA. Ovdje je
-- provjera PRETPLATE, a pristup i dalje čuva zaseban can_access_project poziv
-- u istom upitu. Ne vraćati ovo na LEFT JOIN bez ponovnog čitanja ove bilješke.

-- ---------------------------------------------------------------------------
-- 1) Automatsko praćenje — SECURITY DEFINER okidači, jer redoviti član nema
-- INSERT pravo na project_members (politika traži can_manage_project_members).
-- Bez okidača bi se pratilo mimo volje samo stvaranjem/dodavanjem, a pisanje
-- poruke ili primanje zaduženja ne bi nikoga pretplatilo.
-- ---------------------------------------------------------------------------
create or replace function public.auto_follow_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into project_members (project_id, user_id)
  values (new.project_id, new.author_id)
  on conflict (project_id, user_id) do nothing;
  return new;
end
$$;

drop trigger if exists auto_follow_on_message on public.messages;
create trigger auto_follow_on_message
  after insert on public.messages
  for each row execute function public.auto_follow_on_message();

create or replace function public.auto_follow_on_assign()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assignee_id is not null and new.assignee_id is distinct from old.assignee_id then
    insert into project_members (project_id, user_id)
    values (new.project_id, new.assignee_id)
    on conflict (project_id, user_id) do nothing;
  end if;
  return new;
end
$$;

drop trigger if exists auto_follow_on_assign on public.items;
create trigger auto_follow_on_assign
  after update of assignee_id on public.items
  for each row execute function public.auto_follow_on_assign();

-- ---------------------------------------------------------------------------
-- 2) Ručno praćenje. Otključavanje (unfollow) već pokriva postojeća
-- project_members_delete politika (vlastiti redak) — ne treba joj RPC.
-- ---------------------------------------------------------------------------
create or replace function public.follow_project(p_project uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if not public.can_access_project(p_project) then
    raise exception 'Nemaš pristup ovom projektu';
  end if;

  insert into project_members (project_id, user_id)
  values (p_project, auth.uid())
  on conflict (project_id, user_id) do nothing;
end
$$;

revoke all on function public.follow_project(uuid) from public, anon;
grant execute on function public.follow_project(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) _unread_rows: prefs CTE sa LEFT na INNER JOIN.
-- Redak sada znači "pretplaćen", pa njegov izostanak mora isključiti projekt iz
-- brojanja — obrnuto od B15, gdje je izostanak retka smio isključiti samo
-- POSTAVKE, nikad PRISTUP (koji ionako ide preko zasebnog can_access_project).
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
      -- INNER: bez retka = ne pratiš, dakle bez obavijesti. Pristup se ovdje ne
      -- odlučuje — to radi can_access_project niže, odvojeno.
      join project_members pm
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

-- ---------------------------------------------------------------------------
-- 4) push_recipients: isti prelazak na INNER JOIN, isti razlog.
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
    join project_members pm
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
