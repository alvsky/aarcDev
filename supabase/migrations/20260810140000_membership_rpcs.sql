-- § B12: članstvo se više ne piše izravno.
--
-- Ovo zatvara rupu koja je poništavala sve dosad: project_members INSERT/UPDATE
-- su bili WITH CHECK (true) / USING (true), pa se bilo tko mogao sam ubaciti u
-- bilo koji projekt i postaviti si role='owner'.
--
-- org_members je od B3 bez ijedne politike za pisanje — ostaje tako. Sve
-- promjene članstva idu kroz SECURITY DEFINER RPC-e koji provjeravaju ulogu
-- pozivatelja. Pravilo o zadnjem vlasniku nameće okidač iz B13, na jednom
-- mjestu, pa ga nijedan od ovih puteva ne može zaobići.

-- ---------------------------------------------------------------------------
-- Pomoćne funkcije
-- ---------------------------------------------------------------------------

-- Tko smije upravljati popisom članova privatnog projekta.
-- SECURITY DEFINER je nužan: zove se iz politike NAD project_members i čita istu
-- tablicu, što bi inline rekurziralo u samu sebe.
create or replace function public.can_manage_project_members(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from projects p
     where p.id = pid
       and (
         public.is_org_admin(p.org_id)
         or p.created_by = auth.uid()
         or exists (
           select 1 from project_members pm
            where pm.project_id = p.id and pm.user_id = auth.uid() and pm.role = 'owner'
         )
       )
  )
$$;

-- Na projekt se smije dodati samo netko tko je već član te organizacije.
-- Bez ovoga bi "dodaj člana" bio zaobilaznica za ubacivanje stranca u najam.
create or replace function public.is_project_org_member(pid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id
     where p.id = pid and om.user_id = uid
  )
$$;

-- ---------------------------------------------------------------------------
-- project_members
-- ---------------------------------------------------------------------------
drop policy if exists "Članovi vide listu članova" on public.project_members;
drop policy if exists "Owner upravlja članovima" on public.project_members;
drop policy if exists members_insert on public.project_members;
drop policy if exists members_update on public.project_members;

create policy project_members_select on public.project_members
  for select to authenticated
  using (public.can_access_project(project_id));

create policy project_members_insert on public.project_members
  for insert to authenticated
  with check (
    public.can_manage_project_members(project_id)
    and public.is_project_org_member(project_id, user_id)
  );

create policy project_members_delete on public.project_members
  for delete to authenticated
  using (user_id = auth.uid() or public.can_manage_project_members(project_id));

-- UPDATE je samo za vlastite postavke obavijesti. Redak ograničava politika,
-- STUPCE ograničava grant — RLS ne zna za stupce, pa bi bez ovoga vlastiti
-- redak značio i slobodno postavljanje role='owner'.
create policy project_members_update on public.project_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke update on public.project_members from authenticated;
grant update (badge_enabled, notif_messages, notif_ideas, notif_bugs, notif_tbi)
  on public.project_members to authenticated;

-- ---------------------------------------------------------------------------
-- invitations — izdavanje i povlačenje idu politikom, prihvaćanje kroz RPC
-- (pozivatelj tada još nije član, pa politiku ne bi ni prošao).
-- ---------------------------------------------------------------------------
create policy invitations_insert on public.invitations
  for insert to authenticated
  with check (public.is_org_admin(org_id) and invited_by = auth.uid());

create policy invitations_delete on public.invitations
  for delete to authenticated
  using (public.is_org_admin(org_id));

-- ---------------------------------------------------------------------------
-- RPC: prihvaćanje pozivnice
-- ---------------------------------------------------------------------------
create or replace function public.accept_invitation(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inv     record;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  select * into inv
    from invitations
   where token = p_token and accepted_at is null
   for update;

  if not found then
    raise exception 'Pozivnica ne postoji ili je već iskorištena';
  end if;

  if inv.expires_at < now() then
    raise exception 'Pozivnica je istekla';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  -- ⚠️ Ova provjera vrijedi točno onoliko koliko vrijedi potvrda e-maila pri
  -- registraciji (BACKLOG G2, još nije uključena). Bez nje se netko može
  -- registrirati s tuđom adresom i preuzeti pozivnicu. Token je zasad glavna
  -- zaštita, e-mail je drugi sloj.
  if lower(v_email) is distinct from lower(inv.email) then
    raise exception 'Pozivnica je izdana na drugu e-mail adresu';
  end if;

  -- Postojećem članu se uloga NE snižava ponovnim prihvaćanjem.
  insert into org_members (org_id, user_id, role)
  values (inv.org_id, auth.uid(), inv.role)
  on conflict (org_id, user_id) do nothing;

  update invitations
     set accepted_at = now(), accepted_by = auth.uid()
   where id = inv.id;

  return inv.org_id;
end
$$;

-- ---------------------------------------------------------------------------
-- RPC: promjena uloge
-- ---------------------------------------------------------------------------
create or replace function public.set_member_role(p_org uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_role not in ('owner', 'admin', 'member', 'guest') then
    raise exception 'Nepoznata uloga: %', p_role;
  end if;

  if not public.is_org_admin(p_org) then
    raise exception 'Samo admin ili vlasnik može mijenjati uloge';
  end if;

  select role into target_role
    from org_members where org_id = p_org and user_id = p_user;

  if not found then
    raise exception 'Osoba nije član ove organizacije';
  end if;

  -- Vlasništvo je isključivo vlasnikova ovlast — i dodjela i oduzimanje.
  -- Inače bi admin mogao razvlastiti vlasnika i preuzeti organizaciju.
  if (p_role = 'owner' or target_role = 'owner') and not public.is_org_owner(p_org) then
    raise exception 'Vlasništvo može mijenjati samo vlasnik';
  end if;

  -- Zadnjeg vlasnika štiti okidač iz B13; ovdje se namjerno ne duplicira.
  update org_members set role = p_role
   where org_id = p_org and user_id = p_user;
end
$$;

-- ---------------------------------------------------------------------------
-- RPC: uklanjanje člana (ili vlastiti izlazak)
-- ---------------------------------------------------------------------------
create or replace function public.remove_org_member(p_org uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  select role into target_role
    from org_members where org_id = p_org and user_id = p_user;

  if not found then
    raise exception 'Osoba nije član ove organizacije';
  end if;

  -- Sebe smije ukloniti svatko (izlazak iz organizacije), tuđi redak samo admin.
  if p_user <> auth.uid() and not public.is_org_admin(p_org) then
    raise exception 'Samo admin ili vlasnik može uklanjati članove';
  end if;

  if target_role = 'owner' and not public.is_org_owner(p_org) then
    raise exception 'Vlasnika može ukloniti samo vlasnik';
  end if;

  -- Zaostali project_members redak ionako ne daje pristup — can_access_project
  -- traži i članstvo u organizaciji, pa model pada u sigurnu stranu. Briše se
  -- da ne zavarava popise članova.
  delete from project_members pm
   using projects p
   where pm.project_id = p.id and p.org_id = p_org and pm.user_id = p_user;

  delete from org_members where org_id = p_org and user_id = p_user;
end
$$;

-- ---------------------------------------------------------------------------
-- Prava izvršavanja
--
-- Postgres novoj funkciji zadano daje EXECUTE roli PUBLIC. Kod SECURITY DEFINER
-- funkcije to znači da je smije pozvati i anon. Provjere `auth.uid() is null`
-- gore to hvataju, ali oslanjati se samo na njih je tanko — pa se pravo
-- oduzima i vraća izričito.
-- ---------------------------------------------------------------------------
revoke all on function public.accept_invitation(uuid) from public, anon;
revoke all on function public.set_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.remove_org_member(uuid, uuid) from public, anon;

grant execute on function public.accept_invitation(uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_org_member(uuid, uuid) to authenticated;
