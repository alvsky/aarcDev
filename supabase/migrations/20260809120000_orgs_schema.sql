-- § B3 + B4: sheme za organizacije.
-- Model, uloge i obrazloženje: docs/multi-tenancy.md
--
-- Čisto aditivno: nove tablice i dva nova stupca na projects. Ništa se ne
-- ograničava, nijedna postojeća politika se ne mijenja — aplikacija radi
-- nepromijenjeno. Zatezanje dolazi u B9–B13.
--
-- Sve tri nove tablice dobivaju RLS BEZ ijedne politike = nedostupne s klijenta
-- (zadano-zabranjeno). Politike stižu s B12, kad postoje i RPC-evi za članstvo.

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------
create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text unique,
  plan       text not null default 'free',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.organizations enable row level security;
grant select, insert, update, delete on public.organizations to authenticated;
grant all on public.organizations to service_role;

-- ---------------------------------------------------------------------------
-- org_members — ovdje živi i najam i ovlasti
-- ---------------------------------------------------------------------------
create table public.org_members (
  org_id     uuid not null references public.organizations(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('owner', 'admin', 'member', 'guest')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

-- Obrnuti smjer: "u kojim sam organizacijama" je najčešći upit i vrti se unutar
-- can_access_project, dakle u svakoj politici.
create index org_members_user_idx on public.org_members (user_id, org_id);

alter table public.org_members enable row level security;
grant select, insert, update, delete on public.org_members to authenticated;
grant all on public.org_members to service_role;

-- ---------------------------------------------------------------------------
-- invitations — poziv ide na e-mail, pa osoba ne mora imati račun
-- ---------------------------------------------------------------------------
create table public.invitations (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  email       text not null,
  -- Nema 'owner': vlasništvo se ne dodjeljuje pozivnicom nego naknadno, i to
  -- samo od strane postojećeg vlasnika.
  role        text not null default 'member' check (role in ('admin', 'member', 'guest')),
  -- uuid kao token: 122 bita entropije je dovoljno, a ne treba pgcrypto.
  token       uuid not null unique default gen_random_uuid(),
  invited_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null
);

-- Jedna otvorena pozivnica po e-mailu po organizaciji; prihvaćene se ne broje,
-- pa se ista osoba može ponovno pozvati ako je jednom uklonjena.
create unique index invitations_pending_idx
  on public.invitations (org_id, lower(email))
  where accepted_at is null;

alter table public.invitations enable row level security;
grant select, insert, update, delete on public.invitations to authenticated;
grant all on public.invitations to service_role;

-- ---------------------------------------------------------------------------
-- projects: org_id i visibility
--
-- org_id je zasad NULLABLE — postaje NOT NULL tek u B6, nakon što backfill (B5)
-- prođe i ti potvrdiš brojke.
--
-- visibility default je 'org' da backfill postojećih projekata bude ništica:
-- oni su i dosad bili vidljivi svim članovima. NOVI projekti se iz aplikacije
-- kreiraju kao 'private' i admin ih objavljuje — to provode INSERT politika i
-- okidač iz B10/B10b, ne klijent.
-- ---------------------------------------------------------------------------
alter table public.projects
  add column org_id     uuid references public.organizations(id) on delete cascade,
  add column visibility text not null default 'org'
               check (visibility in ('org', 'private'));

create index projects_org_idx on public.projects (org_id);
