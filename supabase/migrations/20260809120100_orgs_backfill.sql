-- § B5: postojeći podaci u jednu organizaciju.
--
-- Radi se na stvarnim podacima, pa je migracija napisana da se može pokrenuti
-- ponovno bez štete: ako organizacija već postoji, preskače se. Ništa se ne
-- briše ni ne prepisuje — samo se dodaju retci i popunjava projects.org_id.
--
-- Ako ispadne krivo, ispravak je obrisati tu jednu organizaciju (org_members i
-- projects.org_id padnu kaskadno / ostanu prazni) i pokrenuti iznova.

do $$
declare
  v_org   uuid;
  v_owner uuid;
  v_name  text;
  n_members int;
  n_projects int;
begin
  if exists (select 1 from public.organizations) then
    raise notice 'Organizacija već postoji — backfill preskočen.';
    return;
  end if;

  -- Vlasnik = tko je stvorio najstariji projekt. Determinističko i točno za
  -- jednokorisnički početak; ostale uloge se poslije mijenjaju kroz sučelje.
  select created_by into v_owner
    from public.projects
   where created_by is not null
   order by created_at
   limit 1;

  -- Rezerva: nema projekata (nova instalacija) — uzmi bilo koji profil.
  if v_owner is null then
    select id into v_owner from public.profiles limit 1;
  end if;

  if v_owner is null then
    raise notice 'Nema nijednog korisnika — nema što prenijeti.';
    return;
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Moja organizacija')
    into v_name
    from public.profiles where id = v_owner;

  insert into public.organizations (name, created_by)
  values (coalesce(v_name, 'Moja organizacija'), v_owner)
  returning id into v_org;

  -- Članovi = svi koji su član ijednog postojećeg projekta. Namjerno NE svi iz
  -- profiles — netko tko nikad nije bio ni na jednom projektu ne pripada ovamo.
  insert into public.org_members (org_id, user_id, role)
  select distinct v_org, pm.user_id, 'member'
    from public.project_members pm
   where pm.user_id is not null
  on conflict (org_id, user_id) do nothing;

  -- Vlasnik ide zadnji, da nadjača eventualni 'member' redak odozgo.
  insert into public.org_members (org_id, user_id, role)
  values (v_org, v_owner, 'owner')
  on conflict (org_id, user_id) do update set role = 'owner';

  -- Postojeći projekti ostaju vidljivi cijeloj organizaciji (visibility default
  -- 'org'), jer su i dosad bili — ovo im samo dodjeljuje najam.
  update public.projects set org_id = v_org where org_id is null;

  select count(*) into n_members  from public.org_members where org_id = v_org;
  select count(*) into n_projects from public.projects   where org_id = v_org;

  raise notice 'Organizacija "%" — članova: %, projekata: %', v_name, n_members, n_projects;
end $$;

-- ---------------------------------------------------------------------------
-- Provjera: nijedan projekt ne smije ostati bez organizacije prije B6.
-- ---------------------------------------------------------------------------
do $$
declare n int;
begin
  select count(*) into n from public.projects where org_id is null;
  if n > 0 then
    raise exception '% projekata je ostalo bez org_id — B6 (NOT NULL) bi pao', n;
  end if;
end $$;
