-- Tko je koliko puta otvorio koji easter egg, i kada zadnji put.
-- Jedan redak po (korisnik, easter egg); brojač se povećava kroz RPC, pa
-- klijent nikad ne piše izravno (nema utrke "pročitaj pa upiši +1").
--
-- Easter eggovi (CHECK, kao items.kind — novi traži migraciju):
--   logo_confetti  — 5 dodira na logo u zaglavlju (AppHeader.vue)
--   about_polaroid — 5 dodira na broj builda na stranici About (AboutPage.vue)
create table if not exists public.easter_egg_opens (
  user_id         uuid not null references auth.users(id) on delete cascade,
  egg             text not null check (egg in ('logo_confetti', 'about_polaroid')),
  open_count      integer not null default 0,
  first_opened_at timestamptz not null default now(),
  last_opened_at  timestamptz not null default now(),
  primary key (user_id, egg)
);

alter table public.easter_egg_opens enable row level security;
grant select on public.easter_egg_opens to authenticated;
grant all on public.easter_egg_opens to service_role;

-- Svatko vidi samo svoje retke; pregled svih je u dashboardu (service role).
create policy easter_egg_opens_select on public.easter_egg_opens
  for select to authenticated
  using (user_id = auth.uid());

create or replace function public.record_easter_egg(p_egg text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  insert into easter_egg_opens (user_id, egg, open_count)
  values (auth.uid(), p_egg, 1)
  on conflict (user_id, egg) do update
     set open_count     = easter_egg_opens.open_count + 1,
         last_opened_at = now();
end
$$;

revoke all on function public.record_easter_egg(text) from public, anon;
grant execute on function public.record_easter_egg(text) to authenticated;
