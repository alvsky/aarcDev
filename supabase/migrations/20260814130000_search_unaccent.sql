-- K3 dogradnja: obična ILIKE ne prepoznaje "velicina" kao "veličina" —
-- unaccent skida dijakritiku na obje strane usporedbe. RPC umjesto
-- .ilike() izravno na klijentu jer supabase-js query builder ne zna
-- omotati stupac u SQL funkciju; RLS i dalje vrijedi jer je funkcija
-- SECURITY INVOKER (zadano) — obična poruka odabrana u ime pozivatelja,
-- ista pravila pristupa kao dosad (can_access_project preko messages
-- politike).
create extension if not exists unaccent with schema extensions;

create or replace function public.search_messages(p_project uuid, p_query text)
returns setof public.messages
language sql
stable
set search_path = public, extensions
as $$
  select *
    from messages
   where project_id = p_project
     and extensions.unaccent(body) ilike extensions.unaccent('%' || p_query || '%')
   order by created_at desc
   limit 30
$$;

grant execute on function public.search_messages(uuid, text) to authenticated;
