-- Per-kategorija postavke notifikacija (badge_enabled ostaje glavni prekidač po projektu)
alter table "public"."project_members"
  add column "notif_messages" boolean default true,
  add column "notif_ideas" boolean default true,
  add column "notif_bugs" boolean default true,
  add column "notif_tbi" boolean default true;

-- Server-side ukupni unread za korisnika — ista logika kao klijentski fetchUnread():
-- nepročitane poruke (prema message_reads watermarku) + novi itemi (prema item_reads),
-- uz poštivanje badge_enabled i per-kategorija postavki.
-- Koristi ga edge function push-on-message za APNs badge broj.
create or replace function "public"."get_unread_total"("p_user_id" "uuid") returns integer
    language "sql" security definer
    as $$
  select (
    (
      select count(*)
      from messages m
      join project_members pm
        on pm.project_id = m.project_id
       and pm.user_id = p_user_id
       and pm.badge_enabled
       and coalesce(pm.notif_messages, true)
      where m.author_id is distinct from p_user_id
        and not exists (
          select 1 from message_reads r
          where r.user_id = p_user_id
            and r.project_id = m.project_id
            and coalesce(r.idea_id, '00000000-0000-0000-0000-000000000000')
              = coalesce(m.idea_id, '00000000-0000-0000-0000-000000000000')
            and coalesce(r.bug_id, '00000000-0000-0000-0000-000000000000')
              = coalesce(m.bug_id, '00000000-0000-0000-0000-000000000000')
            and coalesce(r.tbi_id, '00000000-0000-0000-0000-000000000000')
              = coalesce(m.tbi_id, '00000000-0000-0000-0000-000000000000')
            and coalesce(r.channel, 'main') = coalesce(m.channel, 'main')
            and r.last_read_at >= m.created_at
        )
    )
    + (
      select count(*)
      from ideas i
      join project_members pm
        on pm.project_id = i.project_id
       and pm.user_id = p_user_id
       and pm.badge_enabled
       and coalesce(pm.notif_ideas, true)
      where i.promoted = false
        and i.created_by is distinct from p_user_id
        and not exists (
          select 1 from item_reads ir
          where ir.user_id = p_user_id and ir.item_id = i.id and ir.item_type = 'idea'
        )
    )
    + (
      select count(*)
      from bugs b
      join project_members pm
        on pm.project_id = b.project_id
       and pm.user_id = p_user_id
       and pm.badge_enabled
       and coalesce(pm.notif_bugs, true)
      where b.status <> 'closed'
        and b.created_by is distinct from p_user_id
        and not exists (
          select 1 from item_reads ir
          where ir.user_id = p_user_id and ir.item_id = b.id and ir.item_type = 'bug'
        )
    )
    + (
      select count(*)
      from tbi_items t
      join project_members pm
        on pm.project_id = t.project_id
       and pm.user_id = p_user_id
       and pm.badge_enabled
       and coalesce(pm.notif_tbi, true)
      where t.status <> 'done'
        and t.created_by is distinct from p_user_id
        and not exists (
          select 1 from item_reads ir
          where ir.user_id = p_user_id and ir.item_id = t.id and ir.item_type = 'tbi'
        )
    )
  )::integer
$$;

grant all on function "public"."get_unread_total"("p_user_id" "uuid") to "anon";
grant all on function "public"."get_unread_total"("p_user_id" "uuid") to "authenticated";
grant all on function "public"."get_unread_total"("p_user_id" "uuid") to "service_role";
