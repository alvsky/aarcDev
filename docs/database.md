# aarcDev — Database

Authoritative source: `supabase/schema.sql` (a dump of the live Supabase project; the single
migration in `supabase/migrations/` is the same dump). This document explains the model —
consult schema.sql for exact DDL.

All primary keys are `uuid` (`gen_random_uuid()`), all timestamps `timestamptz` default
`now()`. Status/priority/role columns are plain `text` with **no CHECK constraints** — valid
values are frontend convention only.

## Entity overview

```
auth.users ──1:1── profiles
    │
    │ created_by / author_id / assignee_id (SET NULL on delete)
    ▼
projects ──< project_members >── auth.users
    │
    ├──< ideas ──────┐ (idea_id, SET NULL)
    ├──< bugs ───────┤ (bug_id,  SET NULL)
    ├──< tbi_items ◄─┘ back-links to source idea/bug
    │
    └──< messages ──< message_reactions
           │ exactly one of idea_id / bug_id / tbi_id (CASCADE),
           │ or none + channel ('main'/'offtopic')
           │
    read tracking: message_reads (per thread), item_reads (per item)
    push: push_tokens (per user device)
```

**Important:** user FKs (`created_by`, `author_id`, `assignee_id`, `user_id`) reference
`auth.users`, **not** `profiles`. PostgREST embeds like `profiles(...)` therefore do not work;
the frontend always joins profiles manually by id list.

## Tables

### profiles
1:1 with `auth.users` (PK = user id, CASCADE). `full_name`, `email`, `avatar_url`, `lang`
(default `'hr'`). Auto-created by the `handle_new_user` trigger on signup, taking `full_name`
from signup metadata or the email local part.

### projects
`name`, `description`, `color` (hex, default `#6366F1`), `created_by`. Deleting a project
cascades to members, ideas, bugs, tbi_items, messages, and read rows.

### project_members
PK `(project_id, user_id)`. `role` = `owner` | `member`. `badge_enabled` (default true) is a
per-user-per-project opt-out that gates **both** unread badge counting and push notifications.
The project creator inserts their own `owner` row right after creating the project (no
trigger does this).

### ideas
`title`, `description`, `promoted` boolean (true once promoted to TBI — the idea row remains),
optional screenshot (`screenshot_url/type/name` pointing into the `chat-attachments` bucket).

### bugs
`priority` (`low`|`med`|`high`, default `med`), `status` (default `open`; lifecycle
`open → confirmed → promoted` / `closed`), `promoted_at`, optional screenshot columns.

### tbi_items
The work backlog ("To Be Implemented"). `status` default `tbi` (other value: `done` with
`completed_at`), `priority` default `med`, `source_type` = `manual` | `idea` | `bug`,
nullable back-links `idea_id` / `bug_id` (SET NULL — the TBI item survives if the source is
deleted), `assignee_id`, `promoted_at`, optional screenshot columns.

### messages
One table for all chat. Thread identity:

- exactly one of `idea_id` / `bug_id` / `tbi_id` set → that item's thread, `channel` null
- all three null → project channel chat, `channel` = `main` (default) or `offtopic`

Also: `author_id`, `body`, attachment columns (`attachment_url/type/name` — storage path, not
public URL), `edited_at`. Item FKs are CASCADE (deleting an item deletes its thread).
`REPLICA IDENTITY FULL` is set so realtime DELETE events carry the full old row.

**Trigger:** `push-on-message` — AFTER INSERT webhook (`supabase_functions.http_request`) to
the `push-on-message` Edge Function URL (project ref is hardcoded in the trigger).

### message_reactions
Emoji reactions; unique `(message_id, user_id, emoji)`. CASCADE from message.

### message_reads
Per user, per thread/channel `last_read_at` watermark. Columns mirror the thread identity of
`messages` (`project_id`, nullable `idea_id`/`bug_id`/`tbi_id`, `channel`).

Uniqueness is a **functional index** (`message_reads_unique`) over
`(user_id, project_id, COALESCE(idea_id, zero-uuid), COALESCE(bug_id, zero-uuid),
COALESCE(tbi_id, zero-uuid), COALESCE(channel, 'main'))`. Because it's expression-based, a
plain PostgREST `.upsert()` cannot target it — **all writes must go through the
`upsert_message_read()` RPC**, which performs the matching `ON CONFLICT` insert.

### item_reads
Per-item "seen" marker: PK `(user_id, item_id, item_type)` with `item_type` =
`idea` | `bug` | `tbi`. Drives the `is_new` flag on cards. Note: `item_id` has no FK to the
item tables (polymorphic), so rows are not cleaned up when items are deleted.

### push_tokens
FCM device tokens: `user_id`, `token` (unique per user+token), `platform` (`ios`|`android`).

### bug_reads, idea_reads — legacy
Per-project `last_read_at` tables from an earlier read-tracking design. Still in the schema,
**not used by the frontend** (superseded by `item_reads` + `message_reads`). Candidates for
removal.

## Views

### thread_message_counts
UNION ALL over `messages` grouped by item: `(project_id, item_id, item_type, message_count)`
for `item_type` in `tbi` | `idea` | `bug`. Used by the stores to show message counts on cards;
TBI cards sum the counts of their own thread plus their linked idea's and bug's threads.

## Functions

| Function | Purpose |
|---|---|
| `handle_new_user()` | Trigger on auth signup → inserts `profiles` row |
| `is_member(pid)` / `is_owner(pid)` | SECURITY DEFINER membership checks used in RLS policies |
| `upsert_message_read(p_user_id, p_project_id, p_idea_id, p_bug_id, p_tbi_id, p_channel)` | The only correct way to write `message_reads` (COALESCE ON CONFLICT) |
| `delete_own_account()` | Deletes `auth.users` row for `auth.uid()` (cascades everywhere). Frontend blocks the call if the user is the sole owner of any project |

## Row Level Security

RLS is enabled on every table, but **most policies are permissive** — current state, not a
mistake to "fix" silently, and not something to rely on:

| Table | Effective access (role `authenticated`) |
|---|---|
| projects | SELECT: creator or member; INSERT: anyone; UPDATE/DELETE: creator |
| project_members | SELECT: members; INSERT/UPDATE: anyone; DELETE: owner (`is_owner`) |
| ideas / bugs | SELECT/INSERT/UPDATE: **anyone**; DELETE: creator |
| tbi_items | SELECT/INSERT/UPDATE: **anyone**; DELETE: creator or member |
| messages | SELECT/INSERT: **anyone**; UPDATE/DELETE: author |
| message_reactions | SELECT: anyone; INSERT/DELETE: own rows |
| profiles | SELECT: **anyone**; UPDATE: own row |
| message_reads / item_reads / push_tokens / bug_reads / idea_reads | own rows only |

So project content (ideas, bugs, TBI, messages, profiles) is readable by **any authenticated
user**, regardless of membership — the app filters by `project_id` client-side. Tightening
these policies to `is_member(project_id)` is a known open TODO.

## Storage

Single bucket **`chat-attachments`** holds both chat attachments and idea/bug/TBI
screenshots. Object paths: `${userId}/${timestamp}.jpg` (images are compressed client-side to
JPEG before upload). The DB stores the **path**, not a URL; the client fetches 1-hour signed
URLs on display. Deleting a chat message or an idea/bug/TBI item removes its storage object
and its local IndexedDB image-cache blob (client-side, in the respective store's delete action).

## Conventions for schema changes

- Keep `schema.sql` in sync (re-dump after changes) — it is the source of truth for tooling.
- New user-reference columns should keep pointing at `auth.users` with `ON DELETE SET NULL`
  (matching existing style), and the frontend must manual-join profiles.
- Enum-like text columns have no constraints; if you add values, update the frontend filters
  and translations (`src/i18n/`).
- Anything that must update `message_reads` needs the RPC, not direct writes.
