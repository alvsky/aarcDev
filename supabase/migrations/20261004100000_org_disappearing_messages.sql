-- Nestajuće poruke: s globalnog prekidača (feature_flags) na postavku po
-- organizaciji. Svaka organizacija sama odlučuje; zadano isključeno, i za
-- postojeće organizacije.
--
-- Pisanje ide postojećom organizations_update politikom (is_org_admin) — ne
-- treba nova. U aplikaciji je prekidač zasad skriven (9 dodira na naziv
-- organizacije u OrgPage.vue), dok ne odlučimo otvoriti ga svima.
alter table public.organizations
  add column if not exists disappearing_messages boolean not null default false;

-- Provjera i na poslužitelju, ne samo skrivanjem gumba: stara verzija
-- aplikacije ili poruka zaglavljena u outboxu iz vremena dok je bilo
-- uključeno ne smije proći u organizaciju koja je to isključila.
create or replace function public.guard_disappearing_messages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.destroy_after_read and not exists (
    select 1
      from public.projects p
      join public.organizations o on o.id = p.org_id
     where p.id = new.project_id
       and o.disappearing_messages
  ) then
    raise exception 'Nestajuće poruke nisu uključene u ovoj organizaciji';
  end if;
  return new;
end
$$;

drop trigger if exists guard_disappearing_messages on public.messages;
create trigger guard_disappearing_messages
  before insert on public.messages
  for each row execute function public.guard_disappearing_messages();

-- Globalni prekidač više ništa ne pali. Tablica feature_flags ostaje za
-- buduće prekidače.
delete from public.feature_flags where key = 'disappearing_messages';
