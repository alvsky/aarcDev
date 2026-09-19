-- Globalni prekidači za funkcije koje se povremeno žele ugasiti/upaliti bez
-- punog deploy ciklusa (App Store review zna trajati danima). Prvi slučaj:
-- poruke koje nestaju nakon čitanja — gumb je bio fizički zakomentiran u
-- MessageInput.vue (2026-09-03), što je značilo da svako ponovno uključivanje
-- traži novi build. Ovo to svodi na jedan red u bazi.
create table if not exists public.feature_flags (
  key        text primary key,
  enabled    boolean not null default false,
  updated_at timestamp with time zone default now(),
  updated_by uuid references auth.users(id)
);

alter table public.feature_flags enable row level security;

-- Svi prijavljeni moraju moći pročitati flag da bi znali sakriti/prikazati
-- funkciju u UI-ju.
create policy "feature_flags_select" on public.feature_flags
  for select to authenticated using (true);

-- Pisanje je namjerno usko: samo admin/owner JEDNE konkretne organizacije
-- (aarc d.o.o.), ne bilo koji org admin. Ovo je developerski prekidač, ne
-- korisnička postavka — otud hardkodirani org_id umjesto is_org_admin() koji
-- bi propustio admina bilo koje organizacije u sustavu.
create policy "feature_flags_update" on public.feature_flags
  for update to authenticated
  using (
    exists (
      select 1 from public.org_members
       where org_id = 'c0f7214b-6d78-4b30-8685-d8cbb4c2ec26'
         and user_id = auth.uid()
         and role in ('owner', 'admin')
    )
  );

insert into public.feature_flags (key, enabled) values
  ('disappearing_messages', false)
on conflict (key) do nothing;
