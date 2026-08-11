-- N1: platforma na kojoj je bug prijavljen. Samo za kind='bug' (frontend to
-- provodi, kolona sama ne zna za kind), ali ipak dobiva CHECK — items već
-- lomi konvenciju "obični tekst bez ograničenja" (invarijanta 8) za vlastiti
-- rječnik (kind/stage/priority), pa je nova mala vrijednost jeftino
-- ograničiti odmah, ne naknadno.
alter table public.items
  add column platform text check (platform is null or platform in ('ios', 'android', 'web'));
