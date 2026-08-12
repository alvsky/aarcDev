-- Koraci za reprodukciju buga. Samo za kind='bug' (frontend to provodi,
-- kolona sama ne zna za kind) — isti obrazac kao items.platform (N1).
--
-- Zasebna kolona, ne dio description: onaj tko popravlja treba odmah vidjeti
-- "kako ovo izazvati" odvojeno od konteksta zašto je prijavljeno, a kasnije
-- se po njoj može provjeriti je li bug uopće reproducibilno prijavljen.
--
-- Bez CHECK-a (za razliku od platform/kind/stage) — slobodan tekst nema
-- rječnik koji bi se ograničavao.
alter table public.items add column steps text;
