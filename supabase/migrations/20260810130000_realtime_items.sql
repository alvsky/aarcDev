-- Popravak: items nikad nije bio dodan u realtime publikaciju.
--
-- Dio 5a je promijenio useRealtime da se pretplaćuje na `items` umjesto na
-- ideas/bugs/tbi_items, ali tablica nije uključena u supabase_realtime. Sve
-- pretplate jednog projekta dijele JEDAN kanal, pa jedna nevaljana tablica ruši
-- cijelu pretplatu — uključujući poruke. Odatle "moram izaći iz chata i vratiti
-- se da vidim vlastitu poruku": fetchMessages radi, živi dotok ne.
--
-- Stare tablice su iz publikacije nestale same kad su obrisane u M6.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'items'
  ) then
    alter publication supabase_realtime add table public.items;
    raise notice 'items dodan u supabase_realtime';
  else
    raise notice 'items je već u publikaciji — bez promjene';
  end if;
end $$;

do $$
declare r record;
begin
  for r in select tablename from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public'
            order by tablename loop
    raise notice 'realtime: %', r.tablename;
  end loop;
end $$;
