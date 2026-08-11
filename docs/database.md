# aarcDev — Database

Authoritative source: `supabase/schema.sql` (a dump of the live Supabase project).
`supabase/migrations/` now holds incremental migrations on top of the original dump. This
document explains the model — consult schema.sql for exact DDL.

All primary keys are `uuid` (`gen_random_uuid()`), all timestamps `timestamptz` default
`now()`. `items.kind`/`stage`/`priority` have CHECK constraints; every other enum-like text
column (`project_members.role`, `push_tokens.platform`) is frontend convention only.

## Entity overview

```
auth.users ──1:1── profiles
    │
    │ created_by / author_id / assignee_id (SET NULL on delete)
    ▼
projects ──< project_members >── auth.users
    │
    ├──< items          one table for ideas, bugs and tasks
    │       │           kind (idea|bug|task) + stage (new…done|rejected)
    │       └──< item_user_state   per-user read_at + watching_at
    │
    └──< messages ──< message_reactions
           │ item_id (CASCADE) for an item thread,
           │ or item_id null + channel ('main'/'offtopic')
           │
    read tracking: message_reads (per thread), item_user_state (per item)
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
cascades to members, items, messages, and read rows.

### project_members

PK `(project_id, user_id)`. `role` = `owner` | `member`. `badge_enabled` (default true) is a
per-user-per-project opt-out that gates **both** unread badge counting and push notifications.
The project creator inserts their own `owner` row right after creating the project (no
trigger does this).

### items

Ideas, bugs and tasks in one table — see `docs/item-model.md` for the reasoning.

- `kind` — `idea` | `bug` | `task`. Set at creation, never changes.
- `stage` — `new` | `confirmed` | `accepted` | `in_progress` | `testing` | `done` | `rejected`.
  The three middle ones are "active work" and make up the TBI board.
- `priority` — `low` | `med` | `high` (default `med`), applies to every kind.
- `assignee_id`, optional screenshot columns.
- Authorship pairs: `created_by`/`created_at` (the original author, never overwritten),
  `accepted_by`/`accepted_at`, `rejected_by`/`rejected_at`, `completed_by`/`completed_at`.

`kind`, `stage` and `priority` carry CHECK constraints — the only enum-like columns in the
schema that do.

Accepting an idea is `stage: new → accepted`: one column, same row, same thread. There is no
separate work-item row and therefore nothing to keep in sync.

### item_user_state

Per-user, per-item state: PK `(user_id, item_id)` with a real FK to `items` (CASCADE).
`read_at` drives the `is_new` flag on cards; `watching_at` is the personal "Pratim" marker
(non-null = watched). Replaced the old polymorphic `item_reads`, which had no FK and orphaned
rows on delete.

### messages

One table for all chat. Thread identity:

- `item_id` set → that item's thread, `channel` null
- `item_id` null → project channel chat, `channel` = `main` (default) or `offtopic`

Also: `author_id`, `body`, attachment columns (`attachment_url/type/name` — storage path, not
public URL), `edited_at`, `reply_to_id`. `item_id` is CASCADE (deleting an item deletes its
thread). `REPLICA IDENTITY FULL` is set so realtime DELETE events carry the full old row.

**Trigger:** `push-on-message` — AFTER INSERT webhook (`supabase_functions.http_request`) to
the `push-on-message` Edge Function URL (project ref is hardcoded in the trigger). `items` has
the same webhook as `push-on-item`; the function branches on `payload.table`.

### message_reactions

Emoji reactions; unique `(message_id, user_id, emoji)`. CASCADE from message.

### message_reads

Per user, per thread/channel `last_read_at` watermark. Columns mirror the thread identity of
`messages` (`project_id`, nullable `item_id`, nullable `channel`).

Uniqueness is a plain unique index over `(user_id, project_id, item_id, channel)` declared
`NULLS NOT DISTINCT`, so nulls compare equal and PostgREST `.upsert()` works directly. The
old expression-based index — and the `upsert_message_read()` RPC it forced, which took a
caller-supplied `p_user_id` with no `auth.uid()` check — are gone.

### push_tokens

FCM device tokens: `user_id`, `token` (unique per user+token), `platform` (`ios`|`android`).

## Views

### item_message_counts

`(item_id, message_count)` grouped over `messages`. Declared `security_invoker = true`, so RLS
on `messages` applies through it — the old `thread_message_counts` did not do this and would
have leaked counts across tenants once BACKLOG § B lands.

One item, one thread, one number. The predecessor was a three-way UNION and TBI cards had to
add up three separate counters.

## Functions

| Function                           | Purpose                                                                                                                                |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `handle_new_user()`                | Trigger on auth signup → inserts `profiles` row                                                                                        |
| `is_member(pid)` / `is_owner(pid)` | SECURITY DEFINER membership checks used in RLS policies on `projects`/`project_members`                                                |
| `can_access_project(pid)`          | The single authorization chokepoint used by every `items` policy. Currently project membership; BACKLOG § B redefines only its body    |
| `delete_own_account()`             | Deletes `auth.users` row for `auth.uid()` (cascades everywhere). Frontend blocks the call if the user is the sole owner of any project |

## Row Level Security

> **Being replaced.** The table below is the current dev-phase state. The target model
> (organizations as tenant, org roles, one `can_access_project()` predicate on every content
> policy) is in `docs/multi-tenancy.md`; migration steps are in `BACKLOG.md` § B. Do not
> tighten these policies ad hoc — do it as that migration.

RLS is enabled on every table, but **most policies are permissive** — current state, not a
mistake to "fix" silently, and not something to rely on:

| Table                                         | Effective access (role `authenticated`)                                |
| --------------------------------------------- | ---------------------------------------------------------------------- |
| projects                                      | SELECT: creator or member; INSERT: **anyone**; UPDATE/DELETE: creator  |
| project_members                               | SELECT: members; INSERT/UPDATE: **anyone**; DELETE: owner (`is_owner`) |
| **items**                                     | **all four gated by `can_access_project()`**; DELETE also creator      |
| messages                                      | SELECT/INSERT: **anyone**; UPDATE/DELETE: author                       |
| message_reactions                             | SELECT: anyone; INSERT/DELETE: own rows                                |
| profiles                                      | SELECT: **anyone**; UPDATE: own row                                    |
| message_reads / item_user_state / push_tokens | own rows only                                                          |

`items` is the exception: it was created after the chokepoint design existed, so it never went
through a permissive phase. Everything older is still open — messages and profiles are readable
by **any authenticated user** regardless of membership, and the app filters client-side.

Two holes worth naming explicitly, because they defeat everything else: `project_members`
INSERT/UPDATE are `WITH CHECK (true)` / `USING (true)`, so any user can join any project and
set their own `role = 'owner'`; and `get_unread_total` is `SECURITY DEFINER` taking a
caller-supplied `p_user_id` with no `auth.uid()` check.

## Storage

Two private buckets (B16, 2026-08-10 — policies live in
`supabase/migrations/20260814100000_storage_policies.sql`, not just the dashboard):

- **`chat-attachments`** — chat attachments and idea/bug/TBI screenshots. Path
  `${projectId}/${userId}/${uuid}.jpg` — the leading `projectId` is what lets RLS scope reads to
  `can_access_project(projectId)` and writes to your own subfolder; the old `${userId}/${file}`
  path (pre-B16) couldn't express that.
- **`avatars`** — profile pictures, not project-scoped. Path `${userId}/${uuid}.jpg`; read policy
  mirrors `profiles_select` (`can_see_profile`) — own avatar or a same-org collaborator's.

Images are compressed client-side to JPEG before upload (`useImageUpload.js`). The DB stores the
**path**, not a URL; the client fetches 1-hour signed URLs on display (`getSignedUrl(path,
bucket)`). Deleting a chat message, an idea/bug/TBI item, or replacing an avatar removes its
storage object and its local IndexedDB image-cache blob (client-side) — delete policy only
allows removing your own subfolder, so an org admin deleting someone else's item leaves their
screenshot orphaned (known, see BACKLOG E3).

## Conventions for schema changes

- Keep `schema.sql` in sync (re-dump after changes) — it is the source of truth for tooling.
- New user-reference columns should keep pointing at `auth.users` with `ON DELETE SET NULL`
  (matching existing style), and the frontend must manual-join profiles.
- Enum-like text columns have no constraints; if you add values, update the frontend filters
  and translations (`src/i18n/`).
- Anything that must update `message_reads` needs the RPC, not direct writes.
