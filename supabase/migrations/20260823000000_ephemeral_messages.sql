alter table public.messages
  add column if not exists destroy_after_read boolean not null default false,
  add column if not exists expires_at timestamptz,
  add column if not exists deleted_at timestamptz;

create table if not exists public.message_user_state (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  hidden_at timestamptz,
  primary key (message_id, user_id)
);

alter table public.message_user_state enable row level security;

create policy message_user_state_own
on public.message_user_state
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant select, insert, update, delete on public.message_user_state to authenticated;
grant all on public.message_user_state to service_role;

create or replace function public.mark_message_read(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_destroy boolean;
begin
  select destroy_after_read into v_destroy
  from public.messages
  where id = p_message_id;

  insert into public.message_user_state (message_id, user_id, read_at)
  values (p_message_id, auth.uid(), now())
  on conflict (message_id, user_id)
  do update set read_at = now();

  if v_destroy then
    update public.message_user_state
    set hidden_at = now()
    where message_id = p_message_id
      and user_id = auth.uid()
      and hidden_at is null;
  end if;
end
$$;

grant execute on function public.mark_message_read(uuid) to authenticated;
grant execute on function public.mark_message_read(uuid) to service_role;
