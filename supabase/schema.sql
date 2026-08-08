


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."delete_own_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."delete_own_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_total"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
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


ALTER FUNCTION "public"."get_unread_total"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1))
  );
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_member"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid()
  )
$$;


ALTER FUNCTION "public"."is_member"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_owner"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid() and role = 'owner'
  )
$$;


ALTER FUNCTION "public"."is_owner"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_message_read"("p_user_id" "uuid", "p_project_id" "uuid", "p_idea_id" "uuid", "p_bug_id" "uuid", "p_tbi_id" "uuid", "p_channel" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into message_reads (user_id, project_id, idea_id, bug_id, tbi_id, channel, last_read_at)
  values (p_user_id, p_project_id, p_idea_id, p_bug_id, p_tbi_id, p_channel, now())
  on conflict (
    user_id,
    project_id,
    coalesce(idea_id, '00000000-0000-0000-0000-000000000000'),
    coalesce(bug_id,  '00000000-0000-0000-0000-000000000000'),
    coalesce(tbi_id,  '00000000-0000-0000-0000-000000000000'),
    coalesce(channel, 'main')
  )
  do update set last_read_at = now();
end;
$$;


ALTER FUNCTION "public"."upsert_message_read"("p_user_id" "uuid", "p_project_id" "uuid", "p_idea_id" "uuid", "p_bug_id" "uuid", "p_tbi_id" "uuid", "p_channel" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."bug_reads" (
    "user_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "last_read_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."bug_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bugs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "title" "text" NOT NULL,
    "description" "text",
    "priority" "text" DEFAULT 'med'::"text",
    "status" "text" DEFAULT 'open'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "promoted_at" timestamp with time zone,
    "screenshot_url" "text",
    "screenshot_type" "text",
    "screenshot_name" "text"
);


ALTER TABLE "public"."bugs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."idea_reads" (
    "user_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "last_read_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."idea_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ideas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "title" "text" NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "promoted" boolean DEFAULT false,
    "screenshot_url" "text",
    "screenshot_type" "text",
    "screenshot_name" "text"
);


ALTER TABLE "public"."ideas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."item_reads" (
    "user_id" "uuid" NOT NULL,
    "item_id" "uuid" NOT NULL,
    "item_type" "text" NOT NULL,
    "read_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."item_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."message_reactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid",
    "user_id" "uuid",
    "emoji" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."message_reactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."message_reads" (
    "user_id" "uuid",
    "project_id" "uuid",
    "idea_id" "uuid",
    "bug_id" "uuid",
    "tbi_id" "uuid",
    "channel" "text" DEFAULT 'main'::"text",
    "last_read_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."message_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "idea_id" "uuid",
    "bug_id" "uuid",
    "tbi_id" "uuid",
    "author_id" "uuid",
    "body" "text",
    "channel" "text" DEFAULT 'main'::"text",
    "attachment_url" "text",
    "attachment_type" "text",
    "attachment_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "edited_at" timestamp with time zone,
    "reply_to_id" "uuid"
);

ALTER TABLE ONLY "public"."messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "email" "text",
    "avatar_url" "text",
    "lang" "text" DEFAULT 'hr'::"text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_members" (
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text",
    "joined_at" timestamp with time zone DEFAULT "now"(),
    "badge_enabled" boolean DEFAULT true,
    "notif_messages" boolean DEFAULT true,
    "notif_ideas" boolean DEFAULT true,
    "notif_bugs" boolean DEFAULT true,
    "notif_tbi" boolean DEFAULT true
);


ALTER TABLE "public"."project_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "color" "text" DEFAULT '#6366F1'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "token" "text" NOT NULL,
    "platform" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tbi_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "title" "text" NOT NULL,
    "description" "text",
    "priority" "text" DEFAULT 'med'::"text",
    "status" "text" DEFAULT 'tbi'::"text",
    "source_type" "text" DEFAULT 'manual'::"text",
    "idea_id" "uuid",
    "bug_id" "uuid",
    "assignee_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "promoted_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "screenshot_url" "text",
    "screenshot_type" "text",
    "screenshot_name" "text"
);


ALTER TABLE "public"."tbi_items" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."thread_message_counts" AS
 SELECT "messages"."project_id",
    "messages"."tbi_id" AS "item_id",
    'tbi'::"text" AS "item_type",
    "count"(*) AS "message_count"
   FROM "public"."messages"
  WHERE ("messages"."tbi_id" IS NOT NULL)
  GROUP BY "messages"."project_id", "messages"."tbi_id"
UNION ALL
 SELECT "messages"."project_id",
    "messages"."idea_id" AS "item_id",
    'idea'::"text" AS "item_type",
    "count"(*) AS "message_count"
   FROM "public"."messages"
  WHERE ("messages"."idea_id" IS NOT NULL)
  GROUP BY "messages"."project_id", "messages"."idea_id"
UNION ALL
 SELECT "messages"."project_id",
    "messages"."bug_id" AS "item_id",
    'bug'::"text" AS "item_type",
    "count"(*) AS "message_count"
   FROM "public"."messages"
  WHERE ("messages"."bug_id" IS NOT NULL)
  GROUP BY "messages"."project_id", "messages"."bug_id";


ALTER VIEW "public"."thread_message_counts" OWNER TO "postgres";


ALTER TABLE ONLY "public"."bug_reads"
    ADD CONSTRAINT "bug_reads_pkey" PRIMARY KEY ("user_id", "project_id");



ALTER TABLE ONLY "public"."bugs"
    ADD CONSTRAINT "bugs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."idea_reads"
    ADD CONSTRAINT "idea_reads_pkey" PRIMARY KEY ("user_id", "project_id");



ALTER TABLE ONLY "public"."ideas"
    ADD CONSTRAINT "ideas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."item_reads"
    ADD CONSTRAINT "item_reads_pkey" PRIMARY KEY ("user_id", "item_id", "item_type");



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_user_id_emoji_key" UNIQUE ("message_id", "user_id", "emoji");



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_pkey" PRIMARY KEY ("project_id", "user_id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_token_key" UNIQUE ("user_id", "token");



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "message_reads_unique" ON "public"."message_reads" USING "btree" ("user_id", "project_id", COALESCE("idea_id", '00000000-0000-0000-0000-000000000000'::"uuid"), COALESCE("bug_id", '00000000-0000-0000-0000-000000000000'::"uuid"), COALESCE("tbi_id", '00000000-0000-0000-0000-000000000000'::"uuid"), COALESCE("channel", 'main'::"text"));



CREATE INDEX "messages_reply_to_id_idx" ON "public"."messages" USING "btree" ("reply_to_id");



CREATE OR REPLACE TRIGGER "push-on-message" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "push-on-idea" AFTER INSERT ON "public"."ideas" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "push-on-bug" AFTER INSERT ON "public"."bugs" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "push-on-tbi" AFTER INSERT ON "public"."tbi_items" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



ALTER TABLE ONLY "public"."bug_reads"
    ADD CONSTRAINT "bug_reads_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bug_reads"
    ADD CONSTRAINT "bug_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bugs"
    ADD CONSTRAINT "bugs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bugs"
    ADD CONSTRAINT "bugs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."idea_reads"
    ADD CONSTRAINT "idea_reads_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."idea_reads"
    ADD CONSTRAINT "idea_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ideas"
    ADD CONSTRAINT "ideas_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ideas"
    ADD CONSTRAINT "ideas_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."item_reads"
    ADD CONSTRAINT "item_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_bug_id_fkey" FOREIGN KEY ("bug_id") REFERENCES "public"."bugs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_idea_id_fkey" FOREIGN KEY ("idea_id") REFERENCES "public"."ideas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_tbi_id_fkey" FOREIGN KEY ("tbi_id") REFERENCES "public"."tbi_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_bug_id_fkey" FOREIGN KEY ("bug_id") REFERENCES "public"."bugs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_idea_id_fkey" FOREIGN KEY ("idea_id") REFERENCES "public"."ideas"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_tbi_id_fkey" FOREIGN KEY ("tbi_id") REFERENCES "public"."tbi_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_assignee_id_fkey" FOREIGN KEY ("assignee_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_bug_id_fkey" FOREIGN KEY ("bug_id") REFERENCES "public"."bugs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_idea_id_fkey" FOREIGN KEY ("idea_id") REFERENCES "public"."ideas"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tbi_items"
    ADD CONSTRAINT "tbi_items_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



CREATE POLICY "Korisnik upravlja vlastitim reads" ON "public"."message_reads" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Korisnik upravlja vlastitim tokenima" ON "public"."push_tokens" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Može kreirati projekt" ON "public"."projects" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Owner upravlja članovima" ON "public"."project_members" FOR DELETE USING ("public"."is_owner"("project_id"));



CREATE POLICY "Vidi projekte u kojima je član" ON "public"."projects" FOR SELECT USING ((("created_by" = "auth"."uid"()) OR ("id" IN ( SELECT "project_members"."project_id"
   FROM "public"."project_members"
  WHERE ("project_members"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."bug_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bug_reads_all" ON "public"."bug_reads" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."bugs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bugs_delete" ON "public"."bugs" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "created_by"));



CREATE POLICY "bugs_insert" ON "public"."bugs" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "bugs_select" ON "public"."bugs" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "bugs_update" ON "public"."bugs" FOR UPDATE TO "authenticated" USING (true);



ALTER TABLE "public"."idea_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "idea_reads_all" ON "public"."idea_reads" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."ideas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ideas_delete" ON "public"."ideas" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "created_by"));



CREATE POLICY "ideas_insert" ON "public"."ideas" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "ideas_select" ON "public"."ideas" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "ideas_update" ON "public"."ideas" FOR UPDATE TO "authenticated" USING (true);



ALTER TABLE "public"."item_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "item_reads_all" ON "public"."item_reads" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "members_insert" ON "public"."project_members" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "members_update" ON "public"."project_members" FOR UPDATE TO "authenticated" USING (true);



ALTER TABLE "public"."message_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."message_reads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_delete" ON "public"."messages" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "author_id"));



CREATE POLICY "messages_insert" ON "public"."messages" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "messages_select" ON "public"."messages" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "messages_update" ON "public"."messages" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "author_id")) WITH CHECK (("auth"."uid"() = "author_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "profiles_update" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."project_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects_delete" ON "public"."projects" FOR DELETE TO "authenticated" USING (("created_by" = "auth"."uid"()));



CREATE POLICY "projects_update" ON "public"."projects" FOR UPDATE TO "authenticated" USING (("created_by" = "auth"."uid"()));



ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reactions_delete" ON "public"."message_reactions" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "reactions_insert" ON "public"."message_reactions" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "reactions_select" ON "public"."message_reactions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "tbi_delete" ON "public"."tbi_items" FOR DELETE TO "authenticated" USING ((("auth"."uid"() = "created_by") OR "public"."is_member"("project_id")));



CREATE POLICY "tbi_insert" ON "public"."tbi_items" FOR INSERT TO "authenticated" WITH CHECK (true);



ALTER TABLE "public"."tbi_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tbi_select" ON "public"."tbi_items" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "tbi_update" ON "public"."tbi_items" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Članovi vide listu članova" ON "public"."project_members" FOR SELECT USING ("public"."is_member"("project_id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unread_total"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unread_total"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread_total"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_message_read"("p_user_id" "uuid", "p_project_id" "uuid", "p_idea_id" "uuid", "p_bug_id" "uuid", "p_tbi_id" "uuid", "p_channel" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_message_read"("p_user_id" "uuid", "p_project_id" "uuid", "p_idea_id" "uuid", "p_bug_id" "uuid", "p_tbi_id" "uuid", "p_channel" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_message_read"("p_user_id" "uuid", "p_project_id" "uuid", "p_idea_id" "uuid", "p_bug_id" "uuid", "p_tbi_id" "uuid", "p_channel" "text") TO "service_role";



GRANT ALL ON TABLE "public"."bug_reads" TO "anon";
GRANT ALL ON TABLE "public"."bug_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."bug_reads" TO "service_role";



GRANT ALL ON TABLE "public"."bugs" TO "anon";
GRANT ALL ON TABLE "public"."bugs" TO "authenticated";
GRANT ALL ON TABLE "public"."bugs" TO "service_role";



GRANT ALL ON TABLE "public"."idea_reads" TO "anon";
GRANT ALL ON TABLE "public"."idea_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."idea_reads" TO "service_role";



GRANT ALL ON TABLE "public"."ideas" TO "anon";
GRANT ALL ON TABLE "public"."ideas" TO "authenticated";
GRANT ALL ON TABLE "public"."ideas" TO "service_role";



GRANT ALL ON TABLE "public"."item_reads" TO "anon";
GRANT ALL ON TABLE "public"."item_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."item_reads" TO "service_role";



GRANT ALL ON TABLE "public"."message_reactions" TO "anon";
GRANT ALL ON TABLE "public"."message_reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."message_reactions" TO "service_role";



GRANT ALL ON TABLE "public"."message_reads" TO "anon";
GRANT ALL ON TABLE "public"."message_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."message_reads" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."project_members" TO "anon";
GRANT ALL ON TABLE "public"."project_members" TO "authenticated";
GRANT ALL ON TABLE "public"."project_members" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."tbi_items" TO "anon";
GRANT ALL ON TABLE "public"."tbi_items" TO "authenticated";
GRANT ALL ON TABLE "public"."tbi_items" TO "service_role";



GRANT ALL ON TABLE "public"."thread_message_counts" TO "anon";
GRANT ALL ON TABLE "public"."thread_message_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."thread_message_counts" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







