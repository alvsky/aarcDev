-- Item model, dio 4: brojanje poruka po stavci.
--
-- Zamjenjuje thread_message_counts, koji je radio UNION preko tri stupca i
-- tjerao TBI karticu da zbraja tri odvojena brojača za jednu stavku. Sada je
-- jedna stavka = jedan thread = jedan broj.
--
-- security_invoker: pogled se izvršava s pravima pozivatelja, pa RLS nad
-- messages vrijedi i kroz njega. Stari pogled to nema — trenutno je svejedno jer
-- je messages_select permisivan, ali nakon BACKLOG § B ne bi bilo.
create or replace view public.item_message_counts
with (security_invoker = true) as
  select item_id, count(*) as message_count
    from public.messages
   where item_id is not null
   group by item_id;

grant select on public.item_message_counts to authenticated;
grant select on public.item_message_counts to service_role;
