-- Brojač poruka na kartici stavke brojao je i potrošene nestajuće poruke.
--
-- Pročitana nestajuća poruka ostaje u messages kao prazan trag (vidi
-- 20260823140000_ephemeral_tombstone.sql), a thread je sakriva kad ju je
-- korisnik otvorio (message_user_state.hidden_at) ili kad su je pročitali svi
-- (messages.deleted_at) — MessageList.vue, isConsumed. Brojač treba brojati
-- isto što korisnik vidi u threadu, pa se ti retci ovdje preskaču.
--
-- security_invoker: auth.uid() je pozivatelj, pa je "potrošena" po korisniku,
-- jednako kao readByMe u chat storeu.
create or replace view public.item_message_counts
with (security_invoker = true) as
  select m.item_id, count(*) as message_count
    from public.messages m
   where m.item_id is not null
     and not (
       m.destroy_after_read
       and (
         m.deleted_at is not null
         or exists (
           select 1
             from public.message_user_state s
            where s.message_id = m.id
              and s.user_id = auth.uid()
              and s.hidden_at is not null
         )
       )
     )
   group by m.item_id;
