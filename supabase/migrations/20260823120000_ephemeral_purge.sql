-- Poruke koje nestaju nakon čitanja: pravo brisanje umjesto skrivanja.
--
-- Dosad je mark_message_read samo upisivao hidden_at u message_user_state, pa
-- je redak (i prilog u Storageu) ostajao zauvijek — poruka je "nestajala" samo
-- iz prikaza. Sad se, kad je pročitaju SVI članovi projekta u kojem je
-- objavljena (bez autora), redak stvarno briše.
--
-- Brisanje samog retka i objekta u Storageu radi edge funkcija purge-message
-- (service_role): chat_attachments_delete politika dopušta brisanje samo iz
-- VLASTITE mape, pa primatelj ne može obrisati autorov screenshot. Ovdje je
-- samo pravilo "je li pročitana do kraja", da ga i RPC i edge funkcija čitaju
-- s istog mjesta.

-- Članstvo u projektu poruke je jedini kriterij: netko tko je u međuvremenu
-- napustio projekt ne blokira brisanje (join na project_members), a ni njegovo
-- čitanje se ne broji.
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
  v_recipients int;
  v_readers int;
begin
  select project_id, author_id, destroy_after_read
    into v_project_id, v_author_id, v_destroy
    from public.messages
   where id = p_message_id;

  if not found or not v_destroy then
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

grant execute on function public.is_message_fully_read(uuid) to authenticated;
grant execute on function public.is_message_fully_read(uuid) to service_role;

-- Povratni tip se mijenja (void -> jsonb), pa funkcija mora prvo pasti.
drop function if exists public.mark_message_read(uuid);

-- Vraća { "fully_read": bool }. Klijent na true pozove purge-message; edge
-- funkcija svejedno ponovno provjeri uvjet, pa lažni poziv ne može ništa.
create or replace function public.mark_message_read(p_message_id uuid)
returns jsonb
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

  if not found then
    return jsonb_build_object('fully_read', false);
  end if;

  insert into public.message_user_state (message_id, user_id, read_at, hidden_at)
  values (p_message_id, auth.uid(), now(), case when v_destroy then now() else null end)
  on conflict (message_id, user_id)
  do update set
    read_at = now(),
    hidden_at = case
      when v_destroy then coalesce(message_user_state.hidden_at, now())
      else message_user_state.hidden_at
    end;

  return jsonb_build_object('fully_read', public.is_message_fully_read(p_message_id));
end
$$;

grant execute on function public.mark_message_read(uuid) to authenticated;
grant execute on function public.mark_message_read(uuid) to service_role;
