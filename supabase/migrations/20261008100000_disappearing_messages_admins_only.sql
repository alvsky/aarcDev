-- Nestajuće poruke smiju slati samo vlasnik i admin organizacije projekta
-- (uz postavku organizations.disappearing_messages, 20261004100000).
--
-- Provjera ide u isti okidač, ne samo skrivanjem vatrice u aplikaciji: stara
-- verzija aplikacije ili poruka zaglavljena u outboxu ne smije je zaobići.
-- is_org_admin gleda auth.uid() (pozivatelja), koji je i autor poruke —
-- security definer ne mijenja auth.uid().
create or replace function public.guard_disappearing_messages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id  uuid;
  v_enabled boolean;
begin
  if not new.destroy_after_read then
    return new;
  end if;

  select o.id, o.disappearing_messages
    into v_org_id, v_enabled
    from public.projects p
    join public.organizations o on o.id = p.org_id
   where p.id = new.project_id;

  if not coalesce(v_enabled, false) then
    raise exception 'Nestajuće poruke nisu uključene u ovoj organizaciji';
  end if;

  if not public.is_org_admin(v_org_id) then
    raise exception 'Nestajuće poruke mogu slati samo vlasnik i admin organizacije';
  end if;

  return new;
end
$$;
