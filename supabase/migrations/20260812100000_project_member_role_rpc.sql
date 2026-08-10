-- B20b: promjena uloge na projektu treba RPC, izravan UPDATE više ne prolazi.
--
-- project_members_update politika (B12) ograničava redak na auth.uid() vlastiti,
-- a GRANT stupce na badge_enabled/notif_* — obje brave zajedno znače da čak ni
-- admin organizacije ne može izravnim UPDATE-om promijeniti tuđu ulogu na
-- projektu. To je namjerno (spriječava da bilo tko sam sebi doda role='owner'
-- kroz vlastiti dopušteni redak), ali znači da ta radnja sad mora ići kroz
-- SECURITY DEFINER funkciju, isti obrazac kao set_member_role za organizacije.

create or replace function public.set_project_member_role(
  p_project uuid,
  p_user    uuid,
  p_role    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_role not in ('owner', 'member') then
    raise exception 'Nepoznata uloga: %', p_role;
  end if;

  if not public.can_manage_project_members(p_project) then
    raise exception 'Nemaš ovlasti za upravljanje članovima ovog projekta';
  end if;

  if not exists (select 1 from project_members where project_id = p_project and user_id = p_user) then
    raise exception 'Osoba nije član ovog projekta';
  end if;

  update project_members set role = p_role
   where project_id = p_project and user_id = p_user;
end
$$;

revoke all on function public.set_project_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.set_project_member_role(uuid, uuid, text) to authenticated;
