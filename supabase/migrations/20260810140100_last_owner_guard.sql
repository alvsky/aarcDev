-- § B13: organizacija uvijek mora imati barem jednog vlasnika.
--
-- Okidač, ne provjera u RPC-u — jer put do razvlaštenja ima više: set_member_role,
-- remove_org_member, izlazak iz organizacije, i kaskadno brisanje org_members kad
-- se briše korisnički račun. Jedno mjesto pokriva sve, uključujući one koje
-- netko doda kasnije.

create or replace function public.guard_last_org_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining int;
begin
  -- Zanima nas samo trenutak kad netko PRESTAJE biti vlasnik.
  if tg_op = 'UPDATE' and (old.role <> 'owner' or new.role = 'owner') then
    return new;
  end if;
  if tg_op = 'DELETE' and old.role <> 'owner' then
    return old;
  end if;

  -- Brisanje cijele organizacije kaskadno briše i njezine članove. Tada nema
  -- što štititi — bez ove grane vlastiti okidač bi onemogućio brisanje
  -- organizacije. Roditeljski redak je u tom trenutku već nestao, jer Postgres
  -- kaskadu izvršava nakon brisanja roditelja.
  if tg_op = 'DELETE'
     and not exists (select 1 from organizations where id = old.org_id) then
    return old;
  end if;

  select count(*) into remaining
    from org_members
   where org_id = old.org_id
     and role = 'owner'
     and user_id <> old.user_id;

  if remaining = 0 then
    raise exception
      'Organizacija mora imati barem jednog vlasnika — prvo dodijeli vlasništvo nekom drugom';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

drop trigger if exists org_members_last_owner_guard on public.org_members;

create trigger org_members_last_owner_guard
  before update or delete on public.org_members
  for each row execute function public.guard_last_org_owner();

-- ---------------------------------------------------------------------------
-- Posljedica koju vrijedi znati (BACKLOG B19):
--
-- org_members.user_id kaskadno prati auth.users. Ako zadnji vlasnik obriše svoj
-- račun, ovaj okidač će to odbiti — što je i namjera, jer bi inače organizacija
-- ostala bez vlasnika. Time je provjera "jedini vlasnik" konačno i na
-- poslužitelju, a ne samo u sučelju.
--
-- Aplikacija tu grešku treba uhvatiti i pokazati čitljivu poruku umjesto sirove
-- Postgres iznimke.
-- ---------------------------------------------------------------------------
