-- § B8: očvršćivanje postojećih is_member / is_owner.
--
-- Ista logika, ista prava — mijenjaju se samo dva modifikatora koja su
-- nedostajala od početka. Bez utjecaja na to tko što vidi.
--
-- `stable`: bez toga su funkcije VOLATILE, pa ih Postgres unutar RLS politike
--   poziva PO SVAKOM RETKU umjesto jednom po upitu. Na tri projekta se ne
--   primijeti; na tisućama poruka je to razlika između upita i zastoja.
--
-- `set search_path = public`: SECURITY DEFINER funkcija bez fiksiranog
--   search_patha je poznat vektor podizanja ovlasti — tko može stvoriti objekt
--   u shemi koja dolazi prije public, može podmetnuti vlastitu tablicu i
--   funkcija će je izvršiti s pravima vlasnika.

create or replace function public.is_member(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid()
  )
$$;

create or replace function public.is_owner(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid() and role = 'owner'
  )
$$;

-- Isti propust ima i can_access_project? Ne — ona je od početka pisana s oba
-- modifikatora (M2). Ovdje se dovodi na razinu samo ono što je starije od nje.
