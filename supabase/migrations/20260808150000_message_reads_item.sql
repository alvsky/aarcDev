-- Item model, dio 5: vodenokazi prelaze na item_id.
--
-- OVDJE PRESTAJE UNATRAG-KOMPATIBILNOST. Stara aplikacija (grana main) nakon
-- ove migracije više ne može označavati pročitano — upsert_message_read se briše.
--
-- Zašto sve odjednom: stari COALESCE indeks tretira redak s postavljenim item_id
-- (a praznim idea/bug/tbi) kao (user, project, 0,0,0, 'main') — što je isti ključ
-- kao čitanje glavnog kanala. Dva modela ne mogu koegzistirati u toj tablici.

-- ---------------------------------------------------------------------------
-- 1) Sažimanje duplikata iz spajanja.
-- Ako je korisnik čitao i thread ideje i thread njezinog TBI-ja, ima dva
-- vodenokaza koji sada pokazuju na istu stavku. Zadržava se NAJSTARIJI: tako se
-- eventualno već pročitane poruke ponovno pokažu kao nepročitane, umjesto da se
-- nepročitane tiho progutaju.
-- ---------------------------------------------------------------------------
with ranked as (
  select ctid,
         row_number() over (
           partition by user_id, project_id, item_id, channel
           order by last_read_at asc nulls first, ctid
         ) as rn
    from public.message_reads
)
delete from public.message_reads m
 using ranked r
 where m.ctid = r.ctid and r.rn > 1;

-- ---------------------------------------------------------------------------
-- 2) Zamjena indeksa.
-- PG 15+ ima NULLS NOT DISTINCT, pa null-ovi u item_id/channel konačno vrijede
-- kao jednaki i indeks može biti OBIČAN, nad stupcima. Time otpada razlog zbog
-- kojeg je pisanje u message_reads uopće moralo ići kroz RPC (invarijanta 3 u
-- CLAUDE.md) — .upsert() sada radi izravno.
-- ---------------------------------------------------------------------------
drop index if exists public.message_reads_unique;

create unique index message_reads_unique
  on public.message_reads (user_id, project_id, item_id, channel)
  nulls not distinct;

-- ---------------------------------------------------------------------------
-- 3) Brisanje RPC-a.
-- Usput zatvara BACKLOG B14: funkcija je bila SECURITY DEFINER i primala
-- p_user_id iz poziva bez ijedne provjere, pa je svatko mogao pisati tuđe
-- vodenokaze. Zamjena je izravan .upsert() koji RLS veže na auth.uid().
-- ---------------------------------------------------------------------------
drop function if exists public.upsert_message_read(uuid, uuid, uuid, uuid, uuid, text);

-- ---------------------------------------------------------------------------
-- Provjera
-- ---------------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from (
    select 1 from public.message_reads
     group by user_id, project_id, item_id, channel
    having count(*) > 1
  ) x;
  if n > 0 then
    raise exception 'Ostalo % skupina duplikata u message_reads', n;
  end if;
end $$;
