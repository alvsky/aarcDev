-- § B7: točka odlučivanja prelazi na organizacije.
--
-- Ovo je prva migracija u § B koja stvarno mijenja tko što vidi. Politike se ne
-- diraju — mijenja se tijelo funkcije koju one već zovu. To je cijela poanta
-- jedne točke odlučivanja (docs/multi-tenancy.md).

-- ---------------------------------------------------------------------------
-- 1) Očuvanje zatečenog pristupa — MORA prije redefinicije funkcije.
--
-- Backfill je svim projektima stavio visibility='org', ali stara politika ih je
-- ograničavala po članstvu NA PROJEKTU. Provjera na stvarnim podacima našla je
-- jedan projekt gdje se to razlikuje ("test" — Anamaria nije član).
--
-- Takvi projekti idu na 'private', pa im postojeći project_members ostaje
-- izričit popis i nitko ne dobiva ništa što dosad nije imao. Širenje pristupa
-- je odluka koja se donosi svjesno, kroz sučelje, a ne usput kroz migraciju —
-- pogotovo jer se čitanje tuđih poruka ne da poništiti.
-- ---------------------------------------------------------------------------
update public.projects p
   set visibility = 'private'
 where p.visibility = 'org'
   and exists (
     select 1
       from public.org_members om
      where om.org_id = p.org_id
        and om.role not in ('owner', 'admin')   -- admini ionako vide sve
        and not exists (
          select 1 from public.project_members pm
           where pm.project_id = p.id and pm.user_id = om.user_id
        )
   );

-- ---------------------------------------------------------------------------
-- 2) Funkcije za prava
-- ---------------------------------------------------------------------------

create or replace function public.is_org_member(oid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from org_members where org_id = oid and user_id = auth.uid()
  )
$$;

create or replace function public.is_org_admin(oid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role in ('owner', 'admin')
  )
$$;

create or replace function public.is_org_owner(oid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role = 'owner'
  )
$$;

-- Jedina funkcija koju politike nad sadržajem uopće zovu. Do sada je gledala
-- članstvo na projektu; od sada organizaciju, vidljivost i ulogu.
--
-- Traži članstvo u organizaciji I (vidljivost ILI izričit redak) — pa zaostali
-- project_members redak za nekoga tko više nije u organizaciji ne daje ništa.
-- Kvar ide u sigurnu stranu.
create or replace function public.can_access_project(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = auth.uid()
    where p.id = pid
      and (
        (p.visibility = 'org' and om.role <> 'guest')
        or om.role in ('owner', 'admin')   -- admini vide sve u svojoj organizaciji
        or exists (
          select 1 from project_members pm
          where pm.project_id = p.id and pm.user_id = auth.uid()
        )
      )
  )
$$;

-- ---------------------------------------------------------------------------
-- 3) Indeksi za putanje kojima funkcije prolaze u svakoj politici.
-- org_members(user_id, org_id) i projects(org_id) postoje od B3.
-- project_members ima PK (project_id, user_id) — obrnuti smjer nema.
-- ---------------------------------------------------------------------------
create index if not exists project_members_user_idx
  on public.project_members (user_id, project_id);

-- ---------------------------------------------------------------------------
-- Izvještaj: koji su projekti završili u kojoj vidljivosti.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select name, visibility from public.projects order by visibility, name loop
    raise notice '% — %', r.visibility, r.name;
  end loop;
end $$;
