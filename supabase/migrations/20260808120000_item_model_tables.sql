-- Item model, dio 2/1: tablice.
-- Model i obrazloženje: docs/item-model.md
-- Ova migracija je čisto aditivna — ideas/bugs/tbi_items ostaju netaknute i
-- aplikacija nastavlja raditi preko njih. Prebacivanje dolazi u dijelu 3.

-- ---------------------------------------------------------------------------
-- Točka odlučivanja o pristupu (docs/multi-tenancy.md).
-- Zasad radi po članstvu u projektu — isto što danas radi is_member(). Migracija
-- na organizacije (BACKLOG § B) mijenja SAMO tijelo ove funkcije; politike koje
-- je koriste ostaju nepromijenjene.
-- `stable` = izračun jednom po upitu umjesto po retku unutar politike.
-- `set search_path` = zatvara vektor podizanja ovlasti kod security definer.
-- ---------------------------------------------------------------------------
create or replace function public.can_access_project(pid uuid)
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

alter function public.can_access_project(uuid) owner to postgres;

-- ---------------------------------------------------------------------------
-- items — jedna tablica za ideje, bugove i zadatke.
-- kind se ne mijenja, stage se mijenja. Promocija = stage 'new' -> 'accepted'.
-- ---------------------------------------------------------------------------
create table public.items (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects(id) on delete cascade,

  kind         text not null check (kind in ('idea', 'bug', 'task')),
  stage        text not null default 'new'
                 check (stage in ('new', 'confirmed', 'accepted', 'done', 'rejected')),
  priority     text not null default 'med' check (priority in ('low', 'med', 'high')),

  title        text not null,
  description  text,
  assignee_id  uuid references auth.users(id) on delete set null,

  -- Autor se NIKAD ne prepisuje; ostale trojke bilježe zadnji prijelaz faze.
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  accepted_by  uuid references auth.users(id) on delete set null,
  accepted_at  timestamptz,
  rejected_by  uuid references auth.users(id) on delete set null,
  rejected_at  timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,

  screenshot_url  text,
  screenshot_type text,
  screenshot_name text
);

create index items_project_kind_stage_idx on public.items (project_id, kind, stage);
create index items_project_stage_idx      on public.items (project_id, stage);
create index items_assignee_idx           on public.items (assignee_id) where assignee_id is not null;

alter table public.items enable row level security;

create policy items_select on public.items
  for select to authenticated
  using (public.can_access_project(project_id));

create policy items_insert on public.items
  for insert to authenticated
  with check (public.can_access_project(project_id));

create policy items_update on public.items
  for update to authenticated
  using (public.can_access_project(project_id))
  with check (public.can_access_project(project_id));

-- Brisanje: autor ili bilo koji član projekta. Prati postojeće tbi_delete
-- pravilo (najblaže od tri stare tablice) da se čišćenje za članom koji je
-- otišao ne zaključa. Pooštriti kad stignu uloge organizacije.
create policy items_delete on public.items
  for delete to authenticated
  using (auth.uid() = created_by or public.can_access_project(project_id));

grant select, insert, update, delete on public.items to authenticated;
grant all on public.items to service_role;

-- ---------------------------------------------------------------------------
-- item_user_state — stanje po korisniku po stavci.
-- Zamjenjuje item_reads i nosi novu oznaku "Pratim" (watching_at).
-- Pravi strani ključ rješava siročad iz BACKLOG C5.
-- ---------------------------------------------------------------------------
create table public.item_user_state (
  user_id     uuid not null references auth.users(id) on delete cascade,
  item_id     uuid not null references public.items(id) on delete cascade,
  read_at     timestamptz,
  watching_at timestamptz,
  primary key (user_id, item_id)
);

create index item_user_state_watching_idx
  on public.item_user_state (user_id) where watching_at is not null;

alter table public.item_user_state enable row level security;

create policy item_user_state_own on public.item_user_state
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.item_user_state to authenticated;
grant all on public.item_user_state to service_role;

-- ---------------------------------------------------------------------------
-- Privremena mapa staro -> novo. Dio 3 preko nje prevezuje poruke.
-- Kod spojenog para DVA retka (ideja i tbi) pokazuju na ISTI item_id — upravo
-- to spaja dva threada u jedan. Briše se na kraju migracije.
-- RLS uključen bez ijedne politike = nedostupno s klijenta (zadano-zabranjeno).
-- ---------------------------------------------------------------------------
-- FK je deferrable jer se stavke i mapa pune unutar jedne naredbe (data-modifying
-- CTE) — provjera se tako odgađa do commita, kad oba retka sigurno postoje.
create table public._item_migration_map (
  old_table text not null check (old_table in ('idea', 'bug', 'tbi')),
  old_id    uuid not null,
  item_id   uuid not null references public.items(id) on delete cascade
              deferrable initially deferred,
  primary key (old_table, old_id)
);

create index item_migration_map_item_idx on public._item_migration_map (item_id);

alter table public._item_migration_map enable row level security;
