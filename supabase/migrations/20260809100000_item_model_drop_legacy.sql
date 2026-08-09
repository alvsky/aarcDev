-- Item model, M6: brisanje starog modela.
--
-- OVA MIGRACIJA JE NEPOVRATNA. Sve dosad je bilo aditivno — od ovog trenutka
-- stari redci više ne postoje i povratka na main nema bez vraćanja snimke baze.
--
-- Redoslijed je bitan: prvo provjere (dok mapa još postoji), zatim push okidač na
-- items (inače push za nove stavke tiho prestane raditi kad padnu stare tablice),
-- pa view koji ovisi o starim stupcima, pa stupci, pa tablice, pa mapa.

-- ---------------------------------------------------------------------------
-- 1) Provjere. Zadnja prilika — mapa se briše na kraju ove migracije.
-- ---------------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from public.ideas i
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'idea' and m.old_id = i.id);
  if n > 0 then raise exception '% ideja nije preneseno u items', n; end if;

  select count(*) into n from public.bugs b
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'bug' and m.old_id = b.id);
  if n > 0 then raise exception '% bugova nije preneseno u items', n; end if;

  select count(*) into n from public.tbi_items t
   where not exists (select 1 from public._item_migration_map m
                      where m.old_table = 'tbi' and m.old_id = t.id);
  if n > 0 then raise exception '% TBI stavki nije preneseno u items', n; end if;

  select count(*) into n from public.messages
   where item_id is null
     and (idea_id is not null or bug_id is not null or tbi_id is not null);
  if n > 0 then raise exception '% poruka još visi na starim vezama', n; end if;

  select count(*) into n from public.message_reads
   where item_id is null
     and (idea_id is not null or bug_id is not null or tbi_id is not null);
  if n > 0 then raise exception '% vodenokaza još visi na starim vezama', n; end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Push okidač na items.
-- Stare tablice imale su svaka svoj okidač (migracija push_for_items). Brisanjem
-- tablica nestaju i oni, pa nasljednika treba postaviti PRIJE toga. Edge funkcija
-- sada grana po payload.table === 'items' i bira kategoriju po kind/stage.
-- Hardkodirani project ref je poznat dug — BACKLOG F1.
-- ---------------------------------------------------------------------------
create or replace trigger "push-on-item"
  after insert on public.items
  for each row
  execute function "supabase_functions"."http_request"(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );

-- ---------------------------------------------------------------------------
-- 3) View koji čita stare stupce.
-- ---------------------------------------------------------------------------
drop view if exists public.thread_message_counts;

-- ---------------------------------------------------------------------------
-- 4) Stari stupci. Brisanjem stupca nestaju i njegovi strani ključevi i indeksi.
-- ---------------------------------------------------------------------------
alter table public.messages
  drop column if exists idea_id,
  drop column if exists bug_id,
  drop column if exists tbi_id;

alter table public.message_reads
  drop column if exists idea_id,
  drop column if exists bug_id,
  drop column if exists tbi_id;

-- ---------------------------------------------------------------------------
-- 5) Stare tablice. bug_reads i idea_reads su naslijeđene i nekorištene —
-- usput zatvara BACKLOG C4.
-- ---------------------------------------------------------------------------
drop table if exists public.item_reads;
drop table if exists public.bug_reads;
drop table if exists public.idea_reads;
drop table if exists public.tbi_items;
drop table if exists public.ideas;
drop table if exists public.bugs;

-- ---------------------------------------------------------------------------
-- 6) Privremena mapa.
-- ---------------------------------------------------------------------------
drop table if exists public._item_migration_map;

-- ---------------------------------------------------------------------------
-- Izvještaj
-- ---------------------------------------------------------------------------
do $$
declare n_items int; n_msg int; n_state int;
begin
  select count(*) into n_items from public.items;
  select count(*) into n_msg from public.messages where item_id is not null;
  select count(*) into n_state from public.item_user_state;
  raise notice 'Stavki: %, poruka u stavkama: %, korisničkih stanja: %', n_items, n_msg, n_state;
end $$;
