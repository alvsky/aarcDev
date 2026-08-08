-- Item model, ispravak: faze moraju pokriti i radna stanja.
--
-- Propust u dijelu 1: rječnik faza složen je prema CLAUDE.md (open/confirmed/
-- promoted/closed), a sučelje za bugove zapravo koristi open/in_progress/
-- testing/closed. Backfill je zato in_progress i testing progutao u 'new', a TBI
-- 'in_progress' spljoštio u 'accepted'.
--
-- Popravljivo je jer stare tablice još postoje i mapa ih veže uz stavke.
--
-- Novi rječnik: new -> confirmed -> accepted -> in_progress -> testing -> done,
-- uz rejected kao izlaz iz bilo koje faze. Tri srednje (accepted, in_progress,
-- testing) zajedno čine "aktivan rad" i sve tri pripadaju TBI ploči.

alter table public.items drop constraint if exists items_stage_check;

alter table public.items add constraint items_stage_check
  check (stage in ('new', 'confirmed', 'accepted', 'in_progress', 'testing', 'done', 'rejected'));

-- ---------------------------------------------------------------------------
-- 1) Bugovi koji nisu spojeni s TBI retkom: vrati im izgubljeno radno stanje.
-- Kod spojenog para fazu diktira TBI redak, pa se oni ovdje namjerno preskaču.
-- ---------------------------------------------------------------------------
update public.items i
   set stage = b.status
  from public._item_migration_map m
  join public.bugs b on b.id = m.old_id and m.old_table = 'bug'
 where i.id = m.item_id
   and b.status in ('in_progress', 'testing')
   and not exists (select 1 from public.tbi_items t where t.bug_id = b.id);

-- ---------------------------------------------------------------------------
-- 2) TBI stavke koje su bile u izradi.
-- ---------------------------------------------------------------------------
update public.items i
   set stage = 'in_progress'
  from public._item_migration_map m
  join public.tbi_items t on t.id = m.old_id and m.old_table = 'tbi'
 where i.id = m.item_id
   and t.status = 'in_progress';

-- ---------------------------------------------------------------------------
-- Izvještaj: koliko je stavki u kojoj fazi nakon ispravka.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select kind, stage, count(*) as n
             from public.items group by kind, stage order by kind, stage loop
    raise notice '% / % : %', r.kind, r.stage, r.n;
  end loop;
end $$;
