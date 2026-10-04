-- Pozivnica se gubila na registraciji s potvrdom e-maila: signUp tada ne vraća
-- sesiju, link za potvrdu vodi na Site URL (statična stranica), pa se korisnik
-- nikad ne vrati na /invite/:token i accept_invitation se nikad ne pozove.
-- Primjer 2026-10-04: račun potvrđen, pozivnica otvorena, org_members prazan.
--
-- Umjesto da se oslanjamo na to da redirect preživi mail, nativnu aplikaciju i
-- statičnu stranicu, klijent pri svakom dohvatu organizacija (orgsStore.fetchOrgs)
-- zove ovu funkciju: sve otvorene, neistekle pozivnice izdane na adresu
-- prijavljenog korisnika postaju članstvo.
--
-- Sigurnost: isto pravilo kao accept_invitation (adresa sesije = adresa
-- pozivnice), ali uz uvjet da je adresa POTVRĐENA — tek tada je dokazano da je
-- korisnik vlasnik adrese (enable_confirmations = true, G2). accept_invitation
-- uz to traži i token; ovdje token nije potreban jer potvrđena adresa jest
-- dokaz da je pozivnica stigla baš toj osobi.
create or replace function public.accept_pending_invitations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_count integer := 0;
  inv     record;
begin
  if auth.uid() is null then
    return 0;
  end if;

  select email into v_email
    from auth.users
   where id = auth.uid()
     and email_confirmed_at is not null;

  if v_email is null then
    return 0;
  end if;

  for inv in
    select *
      from invitations
     where lower(email) = lower(v_email)
       and accepted_at is null
       and expires_at >= now()
     for update
  loop
    -- Postojećem članu se uloga NE snižava (isto kao accept_invitation).
    insert into org_members (org_id, user_id, role)
    values (inv.org_id, auth.uid(), inv.role)
    on conflict (org_id, user_id) do nothing;

    update invitations
       set accepted_at = now(), accepted_by = auth.uid()
     where id = inv.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end
$$;

revoke all on function public.accept_pending_invitations() from public, anon;
grant execute on function public.accept_pending_invitations() to authenticated;
