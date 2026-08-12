


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



CREATE OR REPLACE FUNCTION "public"."_unread_rows"("p_user" "uuid") RETURNS TABLE("project_id" "uuid", "scope" "text", "ref" "text", "tab" "text", "n" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with prefs as (
    select p.id as project_id,
           coalesce(pm.notif_messages, true) as notif_messages,
           coalesce(pm.notif_ideas, true)    as notif_ideas,
           coalesce(pm.notif_bugs, true)     as notif_bugs,
           coalesce(pm.notif_tbi, true)      as notif_tbi
      from projects p
      join org_members om on om.org_id = p.org_id and om.user_id = p_user
      -- INNER: bez retka = ne pratiš, dakle bez obavijesti. Pristup se ovdje ne
      -- odlučuje — to radi can_access_project niže, odvojeno.
      join project_members pm
        on pm.project_id = p.id and pm.user_id = p_user
     where public.can_access_project(p.id, p_user)
       and coalesce(pm.badge_enabled, true)
  ),
  msgs as (
    select m.project_id, m.item_id, m.channel, count(*)::int as n
      from messages m
      join prefs pr on pr.project_id = m.project_id and pr.notif_messages
     where m.author_id is distinct from p_user
       and not exists (
         select 1 from message_reads r
          where r.user_id = p_user
            and r.project_id = m.project_id
            and r.item_id is not distinct from m.item_id
            and r.channel  is not distinct from m.channel
            and r.last_read_at >= m.created_at
       )
     group by m.project_id, m.item_id, m.channel
  ),
  new_items as (
    select i.project_id,
           public.item_tab_new(i.kind, i.stage) as tab,
           count(*)::int as n
      from items i
      join prefs pr on pr.project_id = i.project_id
     where i.created_by is distinct from p_user
       and public.item_tab_new(i.kind, i.stage) is not null
       and case public.item_tab_new(i.kind, i.stage)
             when 'ideas' then pr.notif_ideas
             when 'bugs'  then pr.notif_bugs
             when 'tbi'   then pr.notif_tbi
             else false
           end
       and not exists (
         select 1 from item_user_state s
          where s.user_id = p_user and s.item_id = i.id and s.read_at is not null
       )
     group by i.project_id, public.item_tab_new(i.kind, i.stage)
  )
  select project_id, 'channel'::text, coalesce(channel, 'main'), null::text, n
    from msgs where item_id is null
  union all
  select m.project_id, 'thread'::text, m.item_id::text,
         public.item_tab_thread(i.kind, i.stage), m.n
    from msgs m join items i on i.id = m.item_id
   where m.item_id is not null
  union all
  select project_id, 'item'::text, ''::text, tab, n
    from new_items
$$;


ALTER FUNCTION "public"."_unread_rows"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_invitation"("p_token" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  inv     record;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  select * into inv
    from invitations
   where token = p_token and accepted_at is null
   for update;

  if not found then
    raise exception 'Pozivnica ne postoji ili je već iskorištena';
  end if;

  if inv.expires_at < now() then
    raise exception 'Pozivnica je istekla';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  -- ⚠️ Ova provjera vrijedi točno onoliko koliko vrijedi potvrda e-maila pri
  -- registraciji (BACKLOG G2, još nije uključena). Bez nje se netko može
  -- registrirati s tuđom adresom i preuzeti pozivnicu. Token je zasad glavna
  -- zaštita, e-mail je drugi sloj.
  if lower(v_email) is distinct from lower(inv.email) then
    raise exception 'Pozivnica je izdana na drugu e-mail adresu';
  end if;

  -- Postojećem članu se uloga NE snižava ponovnim prihvaćanjem.
  insert into org_members (org_id, user_id, role)
  values (inv.org_id, auth.uid(), inv.role)
  on conflict (org_id, user_id) do nothing;

  update invitations
     set accepted_at = now(), accepted_by = auth.uid()
   where id = inv.id;

  return inv.org_id;
end
$$;


ALTER FUNCTION "public"."accept_invitation"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_follow_on_assign"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.assignee_id is not null and new.assignee_id is distinct from old.assignee_id then
    insert into project_members (project_id, user_id)
    values (new.project_id, new.assignee_id)
    on conflict (project_id, user_id) do nothing;
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."auto_follow_on_assign"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_follow_on_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into project_members (project_id, user_id)
  values (new.project_id, new.author_id)
  on conflict (project_id, user_id) do nothing;
  return new;
end
$$;


ALTER FUNCTION "public"."auto_follow_on_message"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_access_project"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_access_project(pid, auth.uid())
$$;


ALTER FUNCTION "public"."can_access_project"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_access_project"("pid" "uuid", "uid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = uid
    where p.id = pid
      and (
        (p.visibility = 'org' and om.role <> 'guest')
        or om.role in ('owner', 'admin')
        or exists (
          select 1 from project_members pm
          where pm.project_id = p.id and pm.user_id = uid
        )
      )
  )
$$;


ALTER FUNCTION "public"."can_access_project"("pid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_manage_project_members"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from projects p
     where p.id = pid
       and (
         public.is_org_admin(p.org_id)
         or p.created_by = auth.uid()
         or exists (
           select 1 from project_members pm
            where pm.project_id = p.id and pm.user_id = auth.uid() and pm.role = 'owner'
         )
       )
  )
$$;


ALTER FUNCTION "public"."can_manage_project_members"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_see_org_directory"("oid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role <> 'guest'
  )
$$;


ALTER FUNCTION "public"."can_see_org_directory"("oid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_see_profile"("target" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    target = auth.uid()
    or exists (
      -- Član/admin/vlasnik: svi u zajedničkoj organizaciji
      select 1
        from org_members me
        join org_members them on them.org_id = me.org_id
       where me.user_id = auth.uid()
         and me.role <> 'guest'
         and them.user_id = target
    )
    or exists (
      -- Gost: samo ljudi s kojima dijeli projekt
      select 1
        from project_members mine
        join project_members theirs on theirs.project_id = mine.project_id
       where mine.user_id = auth.uid()
         and theirs.user_id = target
    )
$$;


ALTER FUNCTION "public"."can_see_profile"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization"("p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Naziv organizacije je obavezan';
  end if;

  insert into organizations (name, created_by)
  values (trim(p_name), auth.uid())
  returning id into v_id;

  insert into org_members (org_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end
$$;


ALTER FUNCTION "public"."create_organization"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_project"("p_org" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text", "p_color" "text" DEFAULT '#6366F1'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."create_project"("p_org" "uuid", "p_name" "text", "p_description" "text", "p_color" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_own_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."delete_own_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."follow_project"("p_project" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if not public.can_access_project(p_project) then
    raise exception 'Nemaš pristup ovom projektu';
  end if;

  insert into project_members (project_id, user_id)
  values (p_project, auth.uid())
  on conflict (project_id, user_id) do nothing;
end
$$;


ALTER FUNCTION "public"."follow_project"("p_project" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_invitation_preview"("p_token" "uuid") RETURNS TABLE("org_name" "text", "role" "text", "email" "text", "expires_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select o.name, i.role, i.email, i.expires_at
    from invitations i
    join organizations o on o.id = i.org_id
   where i.token = p_token
     and i.accepted_at is null
     and i.expires_at > now()
$$;


ALTER FUNCTION "public"."get_invitation_preview"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread"() RETURNS TABLE("project_id" "uuid", "scope" "text", "ref" "text", "tab" "text", "n" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select * from public._unread_rows(auth.uid())
$$;


ALTER FUNCTION "public"."get_unread"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_total"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(sum(n), 0)::int from public._unread_rows(p_user_id)
$$;


ALTER FUNCTION "public"."get_unread_total"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_last_org_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."guard_last_org_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_project_visibility"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- Poslužiteljski kontekst (service_role, migracije) nema auth.uid().
  -- Neautentificirani klijent ovdje ne može doći — politike su `to authenticated`.
  if auth.uid() is null then
    return new;
  end if;

  if new.visibility is distinct from old.visibility
     and not public.is_org_admin(new.org_id) then
    raise exception 'Vidljivost projekta može mijenjati samo admin organizacije';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."guard_project_visibility"() OWNER TO "postgres";


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
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid()
  )
$$;


ALTER FUNCTION "public"."is_member"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_org_admin"("oid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role in ('owner', 'admin')
  )
$$;


ALTER FUNCTION "public"."is_org_admin"("oid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_org_member"("oid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from org_members where org_id = oid and user_id = auth.uid()
  )
$$;


ALTER FUNCTION "public"."is_org_member"("oid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_org_owner"("oid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from org_members
     where org_id = oid and user_id = auth.uid() and role = 'owner'
  )
$$;


ALTER FUNCTION "public"."is_org_owner"("oid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_owner"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from project_members
    where project_id = pid and user_id = auth.uid() and role = 'owner'
  )
$$;


ALTER FUNCTION "public"."is_owner"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_project_org_admin"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = auth.uid()
     where p.id = pid and om.role in ('owner', 'admin')
  )
$$;


ALTER FUNCTION "public"."is_project_org_admin"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_project_org_member"("pid" "uuid", "uid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id
     where p.id = pid and om.user_id = uid
  )
$$;


ALTER FUNCTION "public"."is_project_org_member"("pid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."item_tab_new"("p_kind" "text", "p_stage" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when p_stage in ('accepted', 'in_progress', 'testing') then 'tbi'
    when p_stage in ('done', 'rejected')                   then null
    when p_kind = 'bug'                                    then 'bugs'
    when p_kind = 'idea'                                   then 'ideas'
    else null   -- zadatak izvan aktivnog rada nema svoju karticu
  end
$$;


ALTER FUNCTION "public"."item_tab_new"("p_kind" "text", "p_stage" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."item_tab_thread"("p_kind" "text", "p_stage" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when p_stage in ('accepted', 'in_progress', 'testing') then 'tbi'
    when p_kind = 'bug'                                    then 'bugs'
    when p_kind = 'idea'                                   then 'ideas'
    else 'tbi'
  end
$$;


ALTER FUNCTION "public"."item_tab_thread"("p_kind" "text", "p_stage" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."org_member_stats"("p_org" "uuid") RETURNS TABLE("user_id" "uuid", "projects_count" bigint, "ideas_created" bigint, "bugs_created" bigint, "tasks_created" bigint, "assigned_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not is_org_owner(p_org) then
    raise exception 'Samo vlasnik organizacije može vidjeti statistiku';
  end if;

  return query
    select
      om.user_id,
      -- "Aktivan u X projekata" — projekti u kojima je nešto prijavio ili mu
      -- je nešto dodijeljeno, ne project_members (to je od B25 pretplata,
      -- ne stvarna aktivnost).
      count(distinct i.project_id) filter (
        where i.created_by = om.user_id or i.assignee_id = om.user_id
      ) as projects_count,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'idea') as ideas_created,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'bug') as bugs_created,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'task') as tasks_created,
      count(*) filter (where i.assignee_id = om.user_id) as assigned_count
    from org_members om
    left join projects p on p.org_id = om.org_id
    left join items i on i.project_id = p.id
    where om.org_id = p_org
    group by om.user_id;
end;
$$;


ALTER FUNCTION "public"."org_member_stats"("p_org" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_recipients"("p_project" "uuid", "p_exclude" "uuid", "p_field" "text") RETURNS TABLE("user_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select om.user_id
    from projects p
    join org_members om on om.org_id = p.org_id
    join project_members pm
      on pm.project_id = p.id and pm.user_id = om.user_id
   where p.id = p_project
     and om.user_id is distinct from p_exclude
     and public.can_access_project(p.id, om.user_id)
     and coalesce(pm.badge_enabled, true)
     and case p_field
           when 'notif_messages' then coalesce(pm.notif_messages, true)
           when 'notif_ideas'    then coalesce(pm.notif_ideas, true)
           when 'notif_bugs'     then coalesce(pm.notif_bugs, true)
           when 'notif_tbi'      then coalesce(pm.notif_tbi, true)
           else true
         end
$$;


ALTER FUNCTION "public"."push_recipients"("p_project" "uuid", "p_exclude" "uuid", "p_field" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_org_member"("p_org" "uuid", "p_user" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  target_role text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  select role into target_role
    from org_members where org_id = p_org and user_id = p_user;

  if not found then
    raise exception 'Osoba nije član ove organizacije';
  end if;

  -- Sebe smije ukloniti svatko (izlazak iz organizacije), tuđi redak samo admin.
  if p_user <> auth.uid() and not public.is_org_admin(p_org) then
    raise exception 'Samo admin ili vlasnik može uklanjati članove';
  end if;

  if target_role = 'owner' and not public.is_org_owner(p_org) then
    raise exception 'Vlasnika može ukloniti samo vlasnik';
  end if;

  -- Zaostali project_members redak ionako ne daje pristup — can_access_project
  -- traži i članstvo u organizaciji, pa model pada u sigurnu stranu. Briše se
  -- da ne zavarava popise članova.
  delete from project_members pm
   using projects p
   where pm.project_id = p.id and p.org_id = p_org and pm.user_id = p_user;

  delete from org_members where org_id = p_org and user_id = p_user;
end
$$;


ALTER FUNCTION "public"."remove_org_member"("p_org" "uuid", "p_user" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "author_id" "uuid",
    "body" "text",
    "channel" "text" DEFAULT 'main'::"text",
    "attachment_url" "text",
    "attachment_type" "text",
    "attachment_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "edited_at" timestamp with time zone,
    "reply_to_id" "uuid",
    "item_id" "uuid",
    CONSTRAINT "messages_channel_check" CHECK ((("channel" IS NULL) OR ("channel" = ANY (ARRAY['main'::"text", 'offtopic'::"text"]))))
);

ALTER TABLE ONLY "public"."messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_messages"("p_project" "uuid", "p_query" "text") RETURNS SETOF "public"."messages"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'extensions'
    AS $$
  select *
    from messages
   where project_id = p_project
     and extensions.unaccent(body) ilike extensions.unaccent('%' || p_query || '%')
   order by created_at desc
   limit 30
$$;


ALTER FUNCTION "public"."search_messages"("p_project" "uuid", "p_query" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_member_role"("p_org" "uuid", "p_user" "uuid", "p_role" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  target_role text;
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_role not in ('owner', 'admin', 'member', 'guest') then
    raise exception 'Nepoznata uloga: %', p_role;
  end if;

  if not public.is_org_admin(p_org) then
    raise exception 'Samo admin ili vlasnik može mijenjati uloge';
  end if;

  select role into target_role
    from org_members where org_id = p_org and user_id = p_user;

  if not found then
    raise exception 'Osoba nije član ove organizacije';
  end if;

  -- Vlasništvo je isključivo vlasnikova ovlast — i dodjela i oduzimanje.
  -- Inače bi admin mogao razvlastiti vlasnika i preuzeti organizaciju.
  if (p_role = 'owner' or target_role = 'owner') and not public.is_org_owner(p_org) then
    raise exception 'Vlasništvo može mijenjati samo vlasnik';
  end if;

  -- Zadnjeg vlasnika štiti okidač iz B13; ovdje se namjerno ne duplicira.
  update org_members set role = p_role
   where org_id = p_org and user_id = p_user;
end
$$;


ALTER FUNCTION "public"."set_member_role"("p_org" "uuid", "p_user" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_project_member_role"("p_project" "uuid", "p_user" "uuid", "p_role" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Potrebna je prijava';
  end if;

  if p_role not in ('owner', 'member') then
    raise exception 'Nepoznata uloga: %', p_role;
  end if;

  if not public.can_manage_project_members(p_project) then
    raise exception 'Nemaš ovlasti za upravljanje članovima ovog projekta';
  end if;

  if not exists (select 1 from project_members where project_id = p_project and user_id = p_user) then
    raise exception 'Osoba nije član ovog projekta';
  end if;

  update project_members set role = p_role
   where project_id = p_project and user_id = p_user;
end
$$;


ALTER FUNCTION "public"."set_project_member_role"("p_project" "uuid", "p_user" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invited_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '14 days'::interval) NOT NULL,
    "accepted_at" timestamp with time zone,
    "accepted_by" "uuid",
    CONSTRAINT "invitations_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'member'::"text", 'guest'::"text"])))
);


ALTER TABLE "public"."invitations" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."item_message_counts" WITH ("security_invoker"='true') AS
 SELECT "item_id",
    "count"(*) AS "message_count"
   FROM "public"."messages"
  WHERE ("item_id" IS NOT NULL)
  GROUP BY "item_id";


ALTER VIEW "public"."item_message_counts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."item_user_state" (
    "user_id" "uuid" NOT NULL,
    "item_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone,
    "watching_at" timestamp with time zone
);


ALTER TABLE "public"."item_user_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "stage" "text" DEFAULT 'new'::"text" NOT NULL,
    "priority" "text" DEFAULT 'med'::"text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "assignee_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "accepted_by" "uuid",
    "accepted_at" timestamp with time zone,
    "rejected_by" "uuid",
    "rejected_at" timestamp with time zone,
    "completed_by" "uuid",
    "completed_at" timestamp with time zone,
    "screenshot_url" "text",
    "screenshot_type" "text",
    "screenshot_name" "text",
    "platform" "text",
    CONSTRAINT "items_kind_check" CHECK (("kind" = ANY (ARRAY['idea'::"text", 'bug'::"text", 'task'::"text"]))),
    CONSTRAINT "items_platform_check" CHECK ((("platform" IS NULL) OR ("platform" = ANY (ARRAY['ios'::"text", 'android'::"text", 'web'::"text"])))),
    CONSTRAINT "items_priority_check" CHECK (("priority" = ANY (ARRAY['low'::"text", 'med'::"text", 'high'::"text"]))),
    CONSTRAINT "items_stage_check" CHECK (("stage" = ANY (ARRAY['new'::"text", 'confirmed'::"text", 'accepted'::"text", 'in_progress'::"text", 'testing'::"text", 'done'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."items" OWNER TO "postgres";


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
    "channel" "text" DEFAULT 'main'::"text",
    "last_read_at" timestamp with time zone DEFAULT "now"(),
    "item_id" "uuid"
);


ALTER TABLE "public"."message_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."org_members" (
    "org_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "org_members_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'admin'::"text", 'member'::"text", 'guest'::"text"])))
);


ALTER TABLE "public"."org_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text",
    "plan" "text" DEFAULT 'free'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


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
    "notif_tbi" boolean DEFAULT true,
    CONSTRAINT "project_members_role_check" CHECK ((("role" IS NULL) OR ("role" = ANY (ARRAY['owner'::"text", 'member'::"text"]))))
);


ALTER TABLE "public"."project_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_user_state" (
    "user_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "pinned_at" timestamp with time zone
);


ALTER TABLE "public"."project_user_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "color" "text" DEFAULT '#6366F1'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "org_id" "uuid" NOT NULL,
    "visibility" "text" DEFAULT 'org'::"text" NOT NULL,
    CONSTRAINT "projects_visibility_check" CHECK (("visibility" = ANY (ARRAY['org'::"text", 'private'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "token" "text" NOT NULL,
    "platform" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "push_tokens_platform_check" CHECK ((("platform" IS NULL) OR ("platform" = ANY (ARRAY['ios'::"text", 'android'::"text", 'web'::"text"]))))
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."item_user_state"
    ADD CONSTRAINT "item_user_state_pkey" PRIMARY KEY ("user_id", "item_id");



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_user_id_emoji_key" UNIQUE ("message_id", "user_id", "emoji");



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_pkey" PRIMARY KEY ("org_id", "user_id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_pkey" PRIMARY KEY ("project_id", "user_id");



ALTER TABLE ONLY "public"."project_user_state"
    ADD CONSTRAINT "project_user_state_pkey" PRIMARY KEY ("user_id", "project_id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_token_key" UNIQUE ("user_id", "token");



CREATE UNIQUE INDEX "invitations_pending_idx" ON "public"."invitations" USING "btree" ("org_id", "lower"("email")) WHERE ("accepted_at" IS NULL);



CREATE INDEX "item_user_state_watching_idx" ON "public"."item_user_state" USING "btree" ("user_id") WHERE ("watching_at" IS NOT NULL);



CREATE INDEX "items_assignee_idx" ON "public"."items" USING "btree" ("assignee_id") WHERE ("assignee_id" IS NOT NULL);



CREATE INDEX "items_project_kind_stage_idx" ON "public"."items" USING "btree" ("project_id", "kind", "stage");



CREATE INDEX "items_project_stage_idx" ON "public"."items" USING "btree" ("project_id", "stage");



CREATE INDEX "message_reads_item_id_idx" ON "public"."message_reads" USING "btree" ("user_id", "item_id") WHERE ("item_id" IS NOT NULL);



CREATE UNIQUE INDEX "message_reads_unique" ON "public"."message_reads" USING "btree" ("user_id", "project_id", "item_id", "channel") NULLS NOT DISTINCT;



CREATE INDEX "messages_item_id_idx" ON "public"."messages" USING "btree" ("item_id") WHERE ("item_id" IS NOT NULL);



CREATE INDEX "messages_reply_to_id_idx" ON "public"."messages" USING "btree" ("reply_to_id");



CREATE INDEX "org_members_user_idx" ON "public"."org_members" USING "btree" ("user_id", "org_id");



CREATE INDEX "project_members_user_idx" ON "public"."project_members" USING "btree" ("user_id", "project_id");



CREATE INDEX "project_user_state_pinned_idx" ON "public"."project_user_state" USING "btree" ("user_id") WHERE ("pinned_at" IS NOT NULL);



CREATE INDEX "projects_org_idx" ON "public"."projects" USING "btree" ("org_id");



CREATE OR REPLACE TRIGGER "auto_follow_on_assign" AFTER UPDATE OF "assignee_id" ON "public"."items" FOR EACH ROW EXECUTE FUNCTION "public"."auto_follow_on_assign"();



CREATE OR REPLACE TRIGGER "auto_follow_on_message" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."auto_follow_on_message"();



CREATE OR REPLACE TRIGGER "org_members_last_owner_guard" BEFORE DELETE OR UPDATE ON "public"."org_members" FOR EACH ROW EXECUTE FUNCTION "public"."guard_last_org_owner"();



CREATE OR REPLACE TRIGGER "projects_visibility_guard" BEFORE UPDATE ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."guard_project_visibility"();



CREATE OR REPLACE TRIGGER "push-on-item" AFTER INSERT ON "public"."items" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "push-on-message" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_accepted_by_fkey" FOREIGN KEY ("accepted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_invited_by_fkey" FOREIGN KEY ("invited_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."item_user_state"
    ADD CONSTRAINT "item_user_state_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."item_user_state"
    ADD CONSTRAINT "item_user_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_accepted_by_fkey" FOREIGN KEY ("accepted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_assignee_id_fkey" FOREIGN KEY ("assignee_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_completed_by_fkey" FOREIGN KEY ("completed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_rejected_by_fkey" FOREIGN KEY ("rejected_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reactions"
    ADD CONSTRAINT "message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_reads"
    ADD CONSTRAINT "message_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_user_state"
    ADD CONSTRAINT "project_user_state_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_user_state"
    ADD CONSTRAINT "project_user_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Korisnik upravlja vlastitim reads" ON "public"."message_reads" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Korisnik upravlja vlastitim tokenima" ON "public"."push_tokens" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invitations_delete" ON "public"."invitations" FOR DELETE TO "authenticated" USING ("public"."is_org_admin"("org_id"));



CREATE POLICY "invitations_insert" ON "public"."invitations" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_org_admin"("org_id") AND ("invited_by" = "auth"."uid"())));



CREATE POLICY "invitations_select" ON "public"."invitations" FOR SELECT TO "authenticated" USING ("public"."is_org_admin"("org_id"));



ALTER TABLE "public"."item_user_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "item_user_state_own" ON "public"."item_user_state" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "items_delete" ON "public"."items" FOR DELETE TO "authenticated" USING (("public"."can_access_project"("project_id") AND (("auth"."uid"() = "created_by") OR "public"."is_project_org_admin"("project_id"))));



CREATE POLICY "items_insert" ON "public"."items" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_project"("project_id"));



CREATE POLICY "items_select" ON "public"."items" FOR SELECT TO "authenticated" USING ("public"."can_access_project"("project_id"));



CREATE POLICY "items_update" ON "public"."items" FOR UPDATE TO "authenticated" USING ("public"."can_access_project"("project_id")) WITH CHECK ("public"."can_access_project"("project_id"));



ALTER TABLE "public"."message_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."message_reads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_delete" ON "public"."messages" FOR DELETE TO "authenticated" USING ((("author_id" = "auth"."uid"()) AND "public"."can_access_project"("project_id")));



CREATE POLICY "messages_insert" ON "public"."messages" FOR INSERT TO "authenticated" WITH CHECK (("public"."can_access_project"("project_id") AND ("author_id" = "auth"."uid"())));



CREATE POLICY "messages_select" ON "public"."messages" FOR SELECT TO "authenticated" USING ("public"."can_access_project"("project_id"));



CREATE POLICY "messages_update" ON "public"."messages" FOR UPDATE TO "authenticated" USING ((("author_id" = "auth"."uid"()) AND "public"."can_access_project"("project_id"))) WITH CHECK (("author_id" = "auth"."uid"()));



ALTER TABLE "public"."org_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_members_select" ON "public"."org_members" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."can_see_org_directory"("org_id")));



ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organizations_delete" ON "public"."organizations" FOR DELETE TO "authenticated" USING ("public"."is_org_owner"("id"));



CREATE POLICY "organizations_select" ON "public"."organizations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("id"));



CREATE POLICY "organizations_update" ON "public"."organizations" FOR UPDATE TO "authenticated" USING ("public"."is_org_admin"("id")) WITH CHECK ("public"."is_org_admin"("id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING ("public"."can_see_profile"("id"));



CREATE POLICY "profiles_update" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."project_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_members_delete" ON "public"."project_members" FOR DELETE TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."can_manage_project_members"("project_id")));



CREATE POLICY "project_members_insert" ON "public"."project_members" FOR INSERT TO "authenticated" WITH CHECK (("public"."can_manage_project_members"("project_id") AND "public"."is_project_org_member"("project_id", "user_id")));



CREATE POLICY "project_members_select" ON "public"."project_members" FOR SELECT TO "authenticated" USING ("public"."can_access_project"("project_id"));



CREATE POLICY "project_members_update" ON "public"."project_members" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."project_user_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_user_state_own" ON "public"."project_user_state" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects_delete" ON "public"."projects" FOR DELETE TO "authenticated" USING (("public"."is_org_admin"("org_id") OR ("created_by" = "auth"."uid"())));



CREATE POLICY "projects_insert" ON "public"."projects" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_org_member"("org_id") AND (("visibility" = 'private'::"text") OR "public"."is_org_admin"("org_id"))));



CREATE POLICY "projects_select" ON "public"."projects" FOR SELECT TO "authenticated" USING ("public"."can_access_project"("id"));



CREATE POLICY "projects_update" ON "public"."projects" FOR UPDATE TO "authenticated" USING (("public"."is_org_admin"("org_id") OR ("created_by" = "auth"."uid"()))) WITH CHECK (("public"."is_org_admin"("org_id") OR ("created_by" = "auth"."uid"())));



ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reactions_delete" ON "public"."message_reactions" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "reactions_insert" ON "public"."message_reactions" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."messages" "m"
  WHERE ("m"."id" = "message_reactions"."message_id")))));



CREATE POLICY "reactions_select" ON "public"."message_reactions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."messages" "m"
  WHERE ("m"."id" = "message_reactions"."message_id"))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."_unread_rows"("p_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_unread_rows"("p_user" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_invitation"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_token" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_follow_on_assign"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_follow_on_assign"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_follow_on_assign"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_follow_on_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_follow_on_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_follow_on_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."can_access_project"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_access_project"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_access_project"("pid" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_access_project"("pid" "uuid", "uid" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_access_project"("pid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_manage_project_members"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_manage_project_members"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_manage_project_members"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_see_org_directory"("oid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_see_org_directory"("oid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_see_org_directory"("oid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_see_profile"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_see_profile"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_see_profile"("target" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_organization"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_organization"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_project"("p_org" "uuid", "p_name" "text", "p_description" "text", "p_color" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_project"("p_org" "uuid", "p_name" "text", "p_description" "text", "p_color" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_project"("p_org" "uuid", "p_name" "text", "p_description" "text", "p_color" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_own_account"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."follow_project"("p_project" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."follow_project"("p_project" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."follow_project"("p_project" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_invitation_preview"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_invitation_preview"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_invitation_preview"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_invitation_preview"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_unread"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_unread"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_unread_total"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_unread_total"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_last_org_owner"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_last_org_owner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_last_org_owner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_project_visibility"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_project_visibility"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_project_visibility"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_org_admin"("oid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_org_admin"("oid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_org_admin"("oid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_org_member"("oid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_org_member"("oid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_org_member"("oid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_org_owner"("oid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_org_owner"("oid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_org_owner"("oid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_owner"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_project_org_admin"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_project_org_admin"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_project_org_admin"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_project_org_member"("pid" "uuid", "uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_project_org_member"("pid" "uuid", "uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_project_org_member"("pid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."item_tab_new"("p_kind" "text", "p_stage" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."item_tab_new"("p_kind" "text", "p_stage" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."item_tab_new"("p_kind" "text", "p_stage" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."item_tab_thread"("p_kind" "text", "p_stage" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."item_tab_thread"("p_kind" "text", "p_stage" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."item_tab_thread"("p_kind" "text", "p_stage" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."org_member_stats"("p_org" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."org_member_stats"("p_org" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."org_member_stats"("p_org" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_recipients"("p_project" "uuid", "p_exclude" "uuid", "p_field" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_recipients"("p_project" "uuid", "p_exclude" "uuid", "p_field" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_org_member"("p_org" "uuid", "p_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_org_member"("p_org" "uuid", "p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_org_member"("p_org" "uuid", "p_user" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON FUNCTION "public"."search_messages"("p_project" "uuid", "p_query" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_messages"("p_project" "uuid", "p_query" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_messages"("p_project" "uuid", "p_query" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_member_role"("p_org" "uuid", "p_user" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_member_role"("p_org" "uuid", "p_user" "uuid", "p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_member_role"("p_org" "uuid", "p_user" "uuid", "p_role" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_project_member_role"("p_project" "uuid", "p_user" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_project_member_role"("p_project" "uuid", "p_user" "uuid", "p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_project_member_role"("p_project" "uuid", "p_user" "uuid", "p_role" "text") TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."item_message_counts" TO "anon";
GRANT ALL ON TABLE "public"."item_message_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."item_message_counts" TO "service_role";



GRANT ALL ON TABLE "public"."item_user_state" TO "anon";
GRANT ALL ON TABLE "public"."item_user_state" TO "authenticated";
GRANT ALL ON TABLE "public"."item_user_state" TO "service_role";



GRANT ALL ON TABLE "public"."items" TO "anon";
GRANT ALL ON TABLE "public"."items" TO "authenticated";
GRANT ALL ON TABLE "public"."items" TO "service_role";



GRANT ALL ON TABLE "public"."message_reactions" TO "anon";
GRANT ALL ON TABLE "public"."message_reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."message_reactions" TO "service_role";



GRANT ALL ON TABLE "public"."message_reads" TO "anon";
GRANT ALL ON TABLE "public"."message_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."message_reads" TO "service_role";



GRANT ALL ON TABLE "public"."org_members" TO "anon";
GRANT ALL ON TABLE "public"."org_members" TO "authenticated";
GRANT ALL ON TABLE "public"."org_members" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."project_members" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."project_members" TO "authenticated";
GRANT ALL ON TABLE "public"."project_members" TO "service_role";



GRANT UPDATE("badge_enabled") ON TABLE "public"."project_members" TO "authenticated";



GRANT UPDATE("notif_messages") ON TABLE "public"."project_members" TO "authenticated";



GRANT UPDATE("notif_ideas") ON TABLE "public"."project_members" TO "authenticated";



GRANT UPDATE("notif_bugs") ON TABLE "public"."project_members" TO "authenticated";



GRANT UPDATE("notif_tbi") ON TABLE "public"."project_members" TO "authenticated";



GRANT ALL ON TABLE "public"."project_user_state" TO "anon";
GRANT ALL ON TABLE "public"."project_user_state" TO "authenticated";
GRANT ALL ON TABLE "public"."project_user_state" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



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







