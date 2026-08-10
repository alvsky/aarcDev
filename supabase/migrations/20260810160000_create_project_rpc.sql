-- § C2 (+ odblokira kreiranje projekta nakon B10).
--
-- Stari postupak je bio u tri koraka iz klijenta: ubaci projekt, pa dohvati
-- "najnoviji projekt tog korisnika", pa dodaj sebe kao ownera. Tri problema:
--
--   1. org_id se nije slao — nakon B10 politika to odbija (403).
--   2. Projekt nastaje PRIVATAN, pa ga član koji nije admin ne može pročitati
--      dok nema project_members redak — a za taj redak treba id koji ne može
--      dohvatiti. Zaključana petlja.
--   3. "Dohvati najnoviji" je utrka: dva istovremena kreiranja i dobiješ tuđi
--      id, odnosno projekt bez ownera.
--
-- Sve troje nestaje ako se to obavi u jednoj transakciji na poslužitelju.

create or replace function public.create_project(
  p_org         uuid,
  p_name        text,
  p_description text default null,
  p_color       text default '#6366F1'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_id   uuid;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Naziv projekta je obavezan';
  end if;

  select role into v_role
    from org_members where org_id = p_org and user_id = auth.uid();

  if not found then
    raise exception 'Nisi član te organizacije';
  end if;

  if v_role = 'guest' then
    raise exception 'Gost ne može stvarati projekte';
  end if;

  -- Uvijek privatan, bez obzira na ulogu. Objavljivanje organizaciji je zasebna
  -- admin radnja koju čuva okidač projects_visibility_guard (B10b).
  insert into projects (org_id, name, description, color, created_by, visibility)
  values (p_org, trim(p_name), p_description, coalesce(p_color, '#6366F1'), auth.uid(), 'private')
  returning id into v_id;

  -- Isti trenutak, ista transakcija — projekt bez ownera više nije moguć.
  insert into project_members (project_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end
$$;

revoke all on function public.create_project(uuid, text, text, text) from public, anon;
grant execute on function public.create_project(uuid, text, text, text) to authenticated;
