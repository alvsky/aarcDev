-- § B9 + B10 + B10b + B11: politike na organizacijski model.
--
-- Od ove migracije RLS stvarno izolira. Dvije stvari koje se tiho lome ako je
-- politika kriva:
--   * REALTIME poštuje RLS — kriva SELECT politika ne baca grešku nego chat
--     jednostavno prestane primati poruke.
--   * item_message_counts je security_invoker, pa se brojevi poruka od sada
--     računaju kroz iste politike (to je i bila namjera).

-- ---------------------------------------------------------------------------
-- 1) messages
--
-- messages_insert je dosad bio WITH CHECK (true) — što je uz project_id
-- dopuštalo i podmetanje TUĐEG author_id. Oboje se zatvara ovdje.
-- ---------------------------------------------------------------------------
drop policy if exists messages_select on public.messages;
drop policy if exists messages_insert on public.messages;
drop policy if exists messages_update on public.messages;
drop policy if exists messages_delete on public.messages;

create policy messages_select on public.messages
  for select to authenticated
  using (public.can_access_project(project_id));

create policy messages_insert on public.messages
  for insert to authenticated
  with check (public.can_access_project(project_id) and author_id = auth.uid());

create policy messages_update on public.messages
  for update to authenticated
  using (author_id = auth.uid() and public.can_access_project(project_id))
  with check (author_id = auth.uid());

create policy messages_delete on public.messages
  for delete to authenticated
  using (author_id = auth.uid() and public.can_access_project(project_id));

-- ---------------------------------------------------------------------------
-- 2) message_reactions — nema project_id, pa se doseg izvodi kroz poruku.
--
-- Namjerno BEZ ponovnog poziva can_access_project: čitanje messages ovdje već
-- prolazi kroz messages_select, pa nedostupna poruka jednostavno ne postoji za
-- ovaj upit. Jedna provjera umjesto dvije, i doseg se ne može razići s onim nad
-- porukama jer je to doslovno isti propust.
-- ---------------------------------------------------------------------------
drop policy if exists reactions_select on public.message_reactions;
drop policy if exists reactions_insert on public.message_reactions;
drop policy if exists reactions_delete on public.message_reactions;

create policy reactions_select on public.message_reactions
  for select to authenticated
  using (exists (select 1 from public.messages m where m.id = message_id));

create policy reactions_insert on public.message_reactions
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.messages m where m.id = message_id)
  );

create policy reactions_delete on public.message_reactions
  for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) projects (B10)
--
-- SELECT ide kroz istu funkciju kao sadržaj. Rekurzije nema: funkcija je
-- SECURITY DEFINER i izvršava se kao vlasnik tablice, kojemu RLS ne vrijedi.
--
-- INSERT: član smije stvoriti projekt, ali samo privatan. 'org' je admin
-- odluka, jer taj projekt ulazi svima u popis i u brojač.
-- ---------------------------------------------------------------------------
drop policy if exists "Može kreirati projekt" on public.projects;
drop policy if exists "Vidi projekte u kojima je član" on public.projects;
drop policy if exists projects_update on public.projects;
drop policy if exists projects_delete on public.projects;

create policy projects_select on public.projects
  for select to authenticated
  using (public.can_access_project(id));

create policy projects_insert on public.projects
  for insert to authenticated
  with check (
    public.is_org_member(org_id)
    and (visibility = 'private' or public.is_org_admin(org_id))
  );

-- Uređivanje i brisanje: admin bilo koji projekt, član samo svoj. Bez ovoga se
-- ne može počistiti za nekim tko je otišao (BACKLOG B24).
create policy projects_update on public.projects
  for update to authenticated
  using (public.is_org_admin(org_id) or created_by = auth.uid())
  with check (public.is_org_admin(org_id) or created_by = auth.uid());

create policy projects_delete on public.projects
  for delete to authenticated
  using (public.is_org_admin(org_id) or created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) Zaštita vidljivosti (B10b)
--
-- Mora biti okidač, ne WITH CHECK: pravilo se tiče PRIJELAZA, a WITH CHECK vidi
-- samo novi redak — pa bi članu blokirao i obično preimenovanje projekta koji
-- je već podijeljen organizaciji.
-- ---------------------------------------------------------------------------
create or replace function public.guard_project_visibility()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Poslužiteljski kontekst (service_role, migracije) nema auth.uid().
  -- Neautentificirani klijent ovdje ne može doći — politike su `to authenticated`.
  if auth.uid() is null then
    return new;
  end if;

  if new.visibility is distinct from old.visibility
     and not public.is_org_admin(new.org_id) then
    raise exception 'Vidljivost projekta može mijenjati samo admin organizacije';
  end if;

  return new;
end
$$;

drop trigger if exists projects_visibility_guard on public.projects;
create trigger projects_visibility_guard
  before update on public.projects
  for each row execute function public.guard_project_visibility();

-- ---------------------------------------------------------------------------
-- 5) profiles (B11)
--
-- Dosad USING (true) = otvoren adresar e-mailova cijelog sustava.
--
-- Dvije grane jer gost namjerno NE vidi adresar organizacije — vanjski
-- suradnik ne smije vidjeti tko ti sve radi u firmi. Njemu ostaju samo
-- suradnici s projekata na kojima stvarno jest.
--
-- ⚠️ Ovo je politika s najvećim dosegom u aplikaciji: manual profile joins su
-- posvuda. Ako pukne, imena i avatari nestanu na svim ekranima odjednom.
-- ---------------------------------------------------------------------------
create or replace function public.can_see_profile(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    target = auth.uid()
    or exists (
      -- Član/admin/vlasnik: svi u zajedničkoj organizaciji
      select 1
        from org_members me
        join org_members them on them.org_id = me.org_id
       where me.user_id = auth.uid()
         and me.role <> 'guest'
         and them.user_id = target
    )
    or exists (
      -- Gost: samo ljudi s kojima dijeli projekt
      select 1
        from project_members mine
        join project_members theirs on theirs.project_id = mine.project_id
       where mine.user_id = auth.uid()
         and theirs.user_id = target
    )
$$;

drop policy if exists profiles_select on public.profiles;

create policy profiles_select on public.profiles
  for select to authenticated
  using (public.can_see_profile(id));

-- ---------------------------------------------------------------------------
-- 6) Čitanje organizacija i članstva
--
-- Tablice su od B3 imale RLS bez ijedne politike (zadano-zabranjeno). Pisanje
-- ostaje zabranjeno do B12, kad stignu RPC-evi — ovdje se otvara samo čitanje,
-- da prebacivač organizacija i popis članova uopće mogu raditi.
-- ---------------------------------------------------------------------------
create policy organizations_select on public.organizations
  for select to authenticated
  using (public.is_org_member(id));

-- Mora ići kroz SECURITY DEFINER funkciju. Inline `select ... from org_members`
-- unutar politike NAD org_members rekurzivno okida istu politiku i Postgres puca
-- s "infinite recursion detected in policy". Funkcija se izvršava kao vlasnik
-- tablice, kojemu RLS ne vrijedi, pa lanac prekida.
create or replace function public.can_see_org_directory(oid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role <> 'guest'
  )
$$;

create policy org_members_select on public.org_members
  for select to authenticated
  using (
    user_id = auth.uid()                        -- gost mora znati svoju ulogu
    or public.can_see_org_directory(org_id)     -- adresar vide svi osim gostiju
  );

create policy invitations_select on public.invitations
  for select to authenticated
  using (public.is_org_admin(org_id));
