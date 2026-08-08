-- Item model, dio 2/2: prijenos podataka.
-- Pravila preslikavanja: docs/item-model.md
--
-- Ključni dio je SPAJANJE: danas promovirana ideja ima DVA retka (ideja + tbi).
-- Ovdje postaju jedan item, a oba stara id-a upisuju se u mapu prema istom
-- item_id — po tome će dio 3 spojiti oba threada u jedan.
--
-- Blokovi A i B namjerno biraju retke preko "nema tbi retka" umjesto preko
-- zastavice promoted/status: tako i eventualno osirotjeli redak (promoviran, a
-- tbi nedostaje) dobije stavku umjesto da tiho ispadne iz migracije.
--
-- `as materialized` nije kozmetika: src sadrži gen_random_uuid(), a na njega se
-- referira više puta. Bez toga bi ga Postgres smio ugraditi (inline) i generirati
-- RAZLIČITE id-eve za stavku i za mapu — migracija bi tiho pukla u dijelu 3.

-- --------------------------------------------------------------------------
-- A) Ideje bez tbi retka -> kind='idea', stage='new'
-- --------------------------------------------------------------------------
with src as materialized (
  select gen_random_uuid() as new_id, i.*
  from public.ideas i
  where not exists (select 1 from public.tbi_items t where t.idea_id = i.id)
),
ins as (
  insert into public.items (
    id, project_id, kind, stage, title, description,
    created_by, created_at,
    screenshot_url, screenshot_type, screenshot_name
  )
  select new_id, project_id, 'idea', 'new', title, description,
         created_by, coalesce(created_at, now()),
         screenshot_url, screenshot_type, screenshot_name
  from src
  returning 1
)
insert into public._item_migration_map (old_table, old_id, item_id)
select 'idea', id, new_id from src;

-- --------------------------------------------------------------------------
-- B) Bugovi bez tbi retka -> kind='bug'; status -> stage
--    closed -> done (dogovoreno); completed_at ostaje prazan jer bugs nema
--    zabilježen trenutak zatvaranja.
-- --------------------------------------------------------------------------
with src as materialized (
  select gen_random_uuid() as new_id, b.*
  from public.bugs b
  where not exists (select 1 from public.tbi_items t where t.bug_id = b.id)
),
ins as (
  insert into public.items (
    id, project_id, kind, stage, priority, title, description,
    created_by, created_at,
    screenshot_url, screenshot_type, screenshot_name
  )
  select new_id, project_id, 'bug',
         case status
           when 'open'      then 'new'
           when 'confirmed' then 'confirmed'
           when 'closed'    then 'done'
           else 'new'
         end,
         coalesce(priority, 'med'), title, description,
         created_by, coalesce(created_at, now()),
         screenshot_url, screenshot_type, screenshot_name
  from src
  returning 1
)
insert into public._item_migration_map (old_table, old_id, item_id)
select 'bug', id, new_id from src;

-- --------------------------------------------------------------------------
-- C) tbi + ideja -> JEDNA stavka (spajanje)
--    Autorstvo dolazi s ideje, prihvaćanje s tbi retka.
-- --------------------------------------------------------------------------
with src as materialized (
  select gen_random_uuid() as new_id,
         t.id as tbi_id, i.id as idea_id, t.project_id,
         t.title, t.description, t.priority, t.assignee_id, t.status,
         t.created_by as accepted_by, t.promoted_at, t.created_at as tbi_created_at,
         t.completed_at,
         i.created_by as author, i.created_at as authored_at,
         coalesce(t.screenshot_url,  i.screenshot_url)  as shot_url,
         coalesce(t.screenshot_type, i.screenshot_type) as shot_type,
         coalesce(t.screenshot_name, i.screenshot_name) as shot_name
  from public.tbi_items t
  join public.ideas i on i.id = t.idea_id
),
ins as (
  insert into public.items (
    id, project_id, kind, stage, priority, title, description, assignee_id,
    created_by, created_at, accepted_by, accepted_at, completed_at,
    screenshot_url, screenshot_type, screenshot_name
  )
  select new_id, project_id, 'idea',
         case when status = 'done' then 'done' else 'accepted' end,
         coalesce(priority, 'med'), title, description, assignee_id,
         author, coalesce(authored_at, now()),
         accepted_by, coalesce(promoted_at, tbi_created_at, now()), completed_at,
         shot_url, shot_type, shot_name
  from src
  returning 1
),
map_tbi as (
  insert into public._item_migration_map (old_table, old_id, item_id)
  select 'tbi', tbi_id, new_id from src
  returning 1
)
insert into public._item_migration_map (old_table, old_id, item_id)
select 'idea', idea_id, new_id from src;

-- --------------------------------------------------------------------------
-- D) tbi + bug -> JEDNA stavka (spajanje)
-- --------------------------------------------------------------------------
with src as materialized (
  select gen_random_uuid() as new_id,
         t.id as tbi_id, b.id as bug_id, t.project_id,
         t.title, t.description, t.priority, t.assignee_id, t.status,
         t.created_by as accepted_by, t.promoted_at, t.created_at as tbi_created_at,
         t.completed_at,
         b.created_by as author, b.created_at as authored_at,
         coalesce(t.screenshot_url,  b.screenshot_url)  as shot_url,
         coalesce(t.screenshot_type, b.screenshot_type) as shot_type,
         coalesce(t.screenshot_name, b.screenshot_name) as shot_name
  from public.tbi_items t
  join public.bugs b on b.id = t.bug_id
),
ins as (
  insert into public.items (
    id, project_id, kind, stage, priority, title, description, assignee_id,
    created_by, created_at, accepted_by, accepted_at, completed_at,
    screenshot_url, screenshot_type, screenshot_name
  )
  select new_id, project_id, 'bug',
         case when status = 'done' then 'done' else 'accepted' end,
         coalesce(priority, 'med'), title, description, assignee_id,
         author, coalesce(authored_at, now()),
         accepted_by, coalesce(promoted_at, tbi_created_at, now()), completed_at,
         shot_url, shot_type, shot_name
  from src
  returning 1
),
map_tbi as (
  insert into public._item_migration_map (old_table, old_id, item_id)
  select 'tbi', tbi_id, new_id from src
  returning 1
)
insert into public._item_migration_map (old_table, old_id, item_id)
select 'bug', bug_id, new_id from src;

-- --------------------------------------------------------------------------
-- E) Samostalni tbi (ručno unesen) -> kind='task'
--    Bira se po praznim vezama, ne po source_type — veze su ono što stvarno
--    određuje može li se spojiti.
-- --------------------------------------------------------------------------
with src as materialized (
  select gen_random_uuid() as new_id, t.*
  from public.tbi_items t
  where t.idea_id is null and t.bug_id is null
),
ins as (
  insert into public.items (
    id, project_id, kind, stage, priority, title, description, assignee_id,
    created_by, created_at, accepted_by, accepted_at, completed_at,
    screenshot_url, screenshot_type, screenshot_name
  )
  select new_id, project_id, 'task',
         case when status = 'done' then 'done' else 'accepted' end,
         coalesce(priority, 'med'), title, description, assignee_id,
         created_by, coalesce(created_at, now()),
         created_by, coalesce(promoted_at, created_at, now()), completed_at,
         screenshot_url, screenshot_type, screenshot_name
  from src
  returning 1
)
insert into public._item_migration_map (old_table, old_id, item_id)
select 'tbi', id, new_id from src;

-- --------------------------------------------------------------------------
-- F) item_reads -> item_user_state
--    Ako je korisnik pročitao i ideju i njezin tbi, dva stara retka pokazuju na
--    istu stavku — uzima se kasnije čitanje.
-- --------------------------------------------------------------------------
insert into public.item_user_state (user_id, item_id, read_at)
select r.user_id, m.item_id, max(r.read_at)
from public.item_reads r
join public._item_migration_map m
  on m.old_table = r.item_type and m.old_id = r.item_id
group by r.user_id, m.item_id;

-- --------------------------------------------------------------------------
-- Provjere. Ako nešto ne štima, migracija pukne i sve se vrati unatrag —
-- bolje nego tiho nepotpuni podaci.
-- --------------------------------------------------------------------------
do $$
declare
  n_src int; n_map int; n_bad int;
begin
  select (select count(*) from public.ideas)
       + (select count(*) from public.bugs)
       + (select count(*) from public.tbi_items)
    into n_src;

  select count(*) from public._item_migration_map into n_map;
  if n_map <> n_src then
    raise exception 'Mapa ima % redaka, izvornih redaka je % — nije sve preneseno', n_map, n_src;
  end if;

  select count(*) from public.items
   where stage = 'accepted' and accepted_at is null into n_bad;
  if n_bad > 0 then
    raise exception '% stavki je u fazi accepted bez accepted_at', n_bad;
  end if;

  -- Priprema za dio 3: svaka poruka mora imati kamo otići.
  select count(*) from public.messages m
   where (m.idea_id is not null and not exists (
            select 1 from public._item_migration_map
             where old_table = 'idea' and old_id = m.idea_id))
      or (m.bug_id is not null and not exists (
            select 1 from public._item_migration_map
             where old_table = 'bug' and old_id = m.bug_id))
      or (m.tbi_id is not null and not exists (
            select 1 from public._item_migration_map
             where old_table = 'tbi' and old_id = m.tbi_id))
    into n_bad;
  if n_bad > 0 then
    raise exception '% poruka nema odgovarajuću stavku u mapi', n_bad;
  end if;
end $$;
