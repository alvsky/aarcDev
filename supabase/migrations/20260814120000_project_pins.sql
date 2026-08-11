-- Osobna oznaka "Prikvačeno" na Homeu — isti obrazac kao item_user_state
-- (docs/item-model.md "Pratim"): vlastita, po korisniku, ništa ne mijenja
-- za druge, ne dira obavijesti/pristup. Odvojena tablica umjesto stupca na
-- project_members jer taj redak od B25 znači "pretplata" i ne postoji za
-- svaki projekt kojem korisnik ima pristup (org-vidljiv projekt bez ikakve
-- interakcije) — pin mora raditi neovisno o tome je li se to dogodilo.
create table public.project_user_state (
  user_id    uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  pinned_at  timestamptz,
  primary key (user_id, project_id)
);

create index project_user_state_pinned_idx
  on public.project_user_state (user_id) where pinned_at is not null;

alter table public.project_user_state enable row level security;

create policy project_user_state_own on public.project_user_state
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.project_user_state to authenticated;
grant all on public.project_user_state to service_role;
