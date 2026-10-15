-- Snimka zaslona nestajuće poruke (iOS ne da spriječiti snimku, samo je
-- otkriti — vidi usePrivacyScreen.js). Primatelj koji snimi otvorenu poruku
-- prijavi to ovdje, a autor poruke dobije push i obavijest u aplikaciji.
--
-- Zasebna tablica, ne redak u messages: obavijest vidi SAMO autor, ne ulazi u
-- brojače nepročitanog ni u thread, i ne otkriva nestajuće poruke članovima
-- koji ih ni ne smiju slati.
create table if not exists public.message_screenshots (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  project_id  uuid not null references public.projects(id) on delete cascade,
  -- Autor poruke = primatelj obavijesti. Denormalizirano da realtime filter
  -- (author_id=eq.<ja>) i RLS ne trebaju join.
  author_id   uuid not null references auth.users(id) on delete cascade,
  taken_by    uuid not null references auth.users(id) on delete cascade,
  taken_at    timestamptz not null default now(),
  -- Jedna prijava po osobi po poruci — ponovljene snimke ne spamaju autora.
  unique (message_id, taken_by)
);

alter table public.message_screenshots enable row level security;
grant select on public.message_screenshots to authenticated;
grant all on public.message_screenshots to service_role;

-- Čita autor (o kome se radi) i onaj tko je snimio. Pisanje samo kroz RPC.
create policy message_screenshots_select on public.message_screenshots
  for select to authenticated
  using (author_id = auth.uid() or taken_by = auth.uid());

create or replace function public.report_screenshot(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  msg record;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  select id, project_id, author_id, destroy_after_read
    into msg
    from messages
   where id = p_message_id;

  -- Tiho ništa za sve što nije tuđa nestajuća poruka u projektu kojem
  -- pozivatelj ima pristup — nema potrebe javljati grešku klijentu.
  if not found
     or not msg.destroy_after_read
     or msg.author_id = auth.uid()
     or not public.can_access_project(msg.project_id) then
    return;
  end if;

  insert into message_screenshots (message_id, project_id, author_id, taken_by)
  values (msg.id, msg.project_id, msg.author_id, auth.uid())
  on conflict (message_id, taken_by) do nothing;
end
$$;

revoke all on function public.report_screenshot(uuid) from public, anon;
grant execute on function public.report_screenshot(uuid) to authenticated;

-- Obavijest u aplikaciji autoru dok je online.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'message_screenshots'
  ) then
    alter publication supabase_realtime add table public.message_screenshots;
  end if;
end $$;

-- Push autoru: ista Edge Function kao poruke i stavke, grana po payload.table.
create trigger "push-on-screenshot"
  after insert on public.message_screenshots
  for each row
  execute function supabase_functions.http_request(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
