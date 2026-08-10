-- B20: organizacije dobivaju UPDATE/DELETE politike i RPC za stvaranje.
--
-- Do sada je organizations imao samo organizations_select (B9-B11) — nije se
-- mogao preimenovati ni obrisati, i nije postojao način da korisnik stvori
-- DRUGU organizaciju (jedina je nastala kroz backfill, B5). Sve troje treba
-- ekranu organizacije i prebacivaču u zaglavlju.

-- ---------------------------------------------------------------------------
-- 1) Preimenovanje i brisanje.
--
-- Brisanje organizacije kaskadno briše org_members i projects (pa i items,
-- messages preko projects) — to je namjeravano ponašanje "obriši organizaciju",
-- ne slučajna posljedica. guard_last_org_owner (B13) već ima iznimku za ovaj
-- slučaj: kad organizacije više nema, okidač ne pokušava zaštititi zadnjeg
-- vlasnika koji upravo nestaje s njom.
-- ---------------------------------------------------------------------------
create policy organizations_update on public.organizations
  for update to authenticated
  using (public.is_org_admin(id))
  with check (public.is_org_admin(id));

create policy organizations_delete on public.organizations
  for delete to authenticated
  using (public.is_org_owner(id));

-- ---------------------------------------------------------------------------
-- 2) create_organization — isti obrazac kao create_project (C2): organizacija
-- i prvi član (vlasnik) u jednoj transakciji, da ne postoji trenutak u kojem
-- organizacija postoji bez ikoga tko njome upravlja.
-- ---------------------------------------------------------------------------
create or replace function public.create_organization(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Naziv organizacije je obavezan';
  end if;

  insert into organizations (name, created_by)
  values (trim(p_name), auth.uid())
  returning id into v_id;

  insert into org_members (org_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end
$$;

revoke all on function public.create_organization(text) from public, anon;
grant execute on function public.create_organization(text) to authenticated;
