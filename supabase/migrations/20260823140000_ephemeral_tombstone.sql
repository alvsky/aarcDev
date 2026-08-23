-- Poruka koja nestaje nakon čitanja ostavlja trag ("Otvoreno"), pa se redak
-- više ne briše — purge-message mu isprazni sadržaj i postavi deleted_at.
--
-- Posljedica: is_message_fully_read bi za takav redak i dalje vraćala true
-- (destroy_after_read ostaje true, čitanja ostaju upisana), pa bi ga svako
-- sljedeće otvaranje threada slalo u purge iznova. Prazan redak nije "spreman
-- za brisanje" — već je obrisan.
create or replace function public.is_message_fully_read(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_id uuid;
  v_author_id uuid;
  v_destroy boolean;
  v_deleted_at timestamptz;
  v_recipients int;
  v_readers int;
begin
  select project_id, author_id, destroy_after_read, deleted_at
    into v_project_id, v_author_id, v_destroy, v_deleted_at
    from public.messages
   where id = p_message_id;

  if not found or not v_destroy or v_deleted_at is not null then
    return false;
  end if;

  select count(*) into v_recipients
    from public.project_members pm
   where pm.project_id = v_project_id
     and pm.user_id <> v_author_id;

  -- Projekt u kojem je autor jedini član: nema kome nestati, ne briši.
  if v_recipients = 0 then
    return false;
  end if;

  select count(*) into v_readers
    from public.message_user_state s
    join public.project_members pm
      on pm.user_id = s.user_id
     and pm.project_id = v_project_id
   where s.message_id = p_message_id
     and s.user_id <> v_author_id
     and s.hidden_at is not null;

  return v_readers >= v_recipients;
end
$$;
