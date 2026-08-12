# aarcDev — Architecture

aarcDev is a mobile-first collaboration app for small development teams. A **project** is the
central unit; inside a project the team works across four tabs: **Chat** (channels `main` and
`offtopic`), **Bugs**, **Ideas**, and **TBI** ("To Be Implemented" — the work backlog). Ideas
and bugs are accepted onto the TBI board by a stage change, and every item carries one chat thread.

## High-level shape

There is **no custom backend server**. The Vue/Quasar client talks directly to Supabase:

```
┌─────────────────────────────────────────────┐
│  Quasar / Vue 3 app (web + Capacitor iOS/Android)
│
│  Pages & components
│        │  (props/events)
│  Pinia stores  ←──  composables (useRealtime, usePush, useBadge, useImageUpload)
│        │
└────────┼────────────────────────────────────┘
         │ supabase-js (single client, src/boot/supabase.js)
         ▼
┌─────────────────────────────────────────────┐
│  Supabase
│  ├─ Auth (email/password)
│  ├─ Postgres + RLS + SQL functions
│  ├─ Realtime (postgres_changes)
│  ├─ Storage (bucket: chat-attachments)
│  └─ Edge Function: push-on-message ──► FCM v1 ──► iOS/Android devices
└─────────────────────────────────────────────┘
```

All business logic lives in the **Pinia stores** (`src/stores/`). Components never call
Supabase directly; they call store actions. Server-side logic is limited to RLS policies, a
handful of SQL functions (`is_member`, `is_owner`, `can_access_project`,
`delete_own_account`, `handle_new_user`), and one Edge Function for push notifications.

## Layers

| Layer        | Location                        | Role                                                                   |
| ------------ | ------------------------------- | ---------------------------------------------------------------------- |
| Pages        | `src/pages/`                    | Route targets and project tab panels                                   |
| Components   | `src/components/{chat,shared}/` | Presentational + dialogs                                               |
| Stores       | `src/stores/`                   | All data access, business rules, realtime merge logic                  |
| Composables  | `src/composables/`              | Cross-cutting: realtime wiring, push, badge, image upload, date format |
| Boot         | `src/boot/`                     | Supabase client singleton, vue-i18n (en default, hr fallback)          |
| Native shell | `src-capacitor/`                | Capacitor 8 iOS/Android projects, Firebase config                      |

## Key data-flow patterns

### Manual profile joins

`created_by` / `author_id` / `assignee_id` foreign keys reference `auth.users`, **not**
`public.profiles`. PostgREST therefore cannot embed profiles (`profiles(...)` fails). Every
store follows the same pattern: fetch domain rows → collect user ids → fetch `profiles` by id
list → merge client-side into a `profiles` (and `assignee`) property on each row. Any new
query that needs author names must repeat this pattern.

### Realtime as the write-echo

`useRealtime(projectId, handlers)` opens one Supabase channel per project subscribing to
INSERT/UPDATE/DELETE on `messages` and `items`, filtered by `project_id`. Each store exposes
`handleIncoming({ event, payload })` that merges the event into local state (deduplicating by
id).

Consequence: after a write such as `chatStore.sendMessage`, the store deliberately does
**not** refetch — the realtime INSERT event is what appends the message locally. ProjectPage
additionally opens two unfiltered channels: message UPDATEs (edits) and `message_reactions`.
`messages` has `REPLICA IDENTITY FULL` so DELETE events carry the old row.

### Chat threading model

A single `messages` table serves every conversation. Thread identity:

- `item_id` set → that item's thread, `channel` is null
- `item_id` null → project channel chat, `channel` = `main` or `offtopic`

The chat store mirrors this with a `threads` dictionary keyed by `${projectId}:item:${id}` or
`${projectId}:${channel}` (`chatStore.threadKey()`).

There used to be three parallel item columns, which meant a promoted idea owned two threads
and the TBI screen had to merge them by hand. That is gone — see `docs/item-model.md`.

### Unread tracking (two mechanisms)

1. **Per-thread message reads** — `message_reads` rows store `last_read_at` per user per
   thread/channel, written with a plain `.upsert()` (the unique index is `NULLS NOT
DISTINCT`). Marked when a channel or thread is opened.
2. **Per-item "NEW" flags** — `item_user_state.read_at` marks an item as seen; stores compute
   `is_new` from it. The same table carries `watching_at`, the personal "Pratim" marker.

`notificationsStore.fetchUnread()` recomputes the whole unread picture **client-side**: it
fetches all messages authored by others, all the user's reads, and all open items, honors the
per-member `badge_enabled` flag, and produces per-project totals plus per-thread and per-tab
counts. It runs after nearly every realtime event and is the single source for tab badges,
project-card badges, and the native app-icon badge. This is a known scaling bottleneck.

## Routing and the project screen

History-mode router (`src/router/index.js`, switched from hash mode 2026-08-12 — a hash-mode
`#` collided with Supabase's own `#access_token=...` auth redirects, see BACKLOG G1). Needs a
SPA fallback (serve `index.html` for any path) on whatever static host it deploys to. A global
guard lazily runs `auth.init()` and redirects unauthenticated users to `/login`.

`/project/:id/:tab(chat|bugs|ideas|tbi)?` renders `ProjectPage.vue`, which does **not** use
nested routes: it renders its own `q-tabs` + keep-alive `q-tab-panels`, mounting
ChatPage/IdeasPage/BugsPage/TbiPage as plain components with a `projectId` prop. The active tab
is a writable computed over `route.params.tab` (I1, 2026-08-11) — tab switches use
`router.replace`, so they don't pile up back-button history but do show up in the URL.
ProjectPage is also where realtime channels are set up and torn down.

## Stage transitions

There is no promotion in the copying sense. An item's `stage` changes and the tab filters do
the rest — same row, same thread, same id.

- **Accept:** `stage → accepted`, records `accepted_by`/`accepted_at`. The item leaves the
  Ideas funnel and appears on the TBI board.
- **Reject / Reopen:** `stage → rejected` or back to `new`. Nothing is deleted, so a rejected
  item keeps its conversation and can come back.
- **Done:** `stage → done` with `completed_by`/`completed_at`.

Always through the store actions (`accept`/`reject`/`reopen`/`markDone`), never a raw update —
the `*_by`/`*_at` columns are written alongside the stage.

Message counts come from the `item_message_counts` view: one item, one thread, one number.

## Push notification pipeline

```
messages INSERT ─┐   ("push-on-message")
items    INSERT ─┤   ("push-on-item")
                 └─ DB webhook trigger
       └─ Edge Function supabase/functions/push-on-message/
            ├─ branch on payload.table; for items pick the
            │  category from kind/stage, same rule as the badge
            ├─ load project name, author name
            ├─ members with badge_enabled = true (excluding author)
            ├─ their push_tokens
            ├─ mint Google OAuth token from FIREBASE_SERVICE_ACCOUNT (manual RS256 JWT)
            └─ FCM v1 send per token (iOS: APNs alert+badge, Android: default sound)
```

Token registration: on app start, `usePush().init()` requests permission and registers.
**Android** receives the token through the standard Capacitor `registration` listener.
**iOS** gets it natively in `AppDelegate.swift` (FirebaseMessaging) and bridges it to the
web view via `localStorage.setItem('fcmToken', …)`; `usePush` polls localStorage for up to
30 s. Tokens upsert into `push_tokens` (unique per user+token).

The `@capawesome/capacitor-badge` plugin mirrors the total unread count onto the app icon;
the badge is cleared and recomputed on app resume (`App.vue`).

## Native vs web builds

`quasar.config.js` unconditionally aliases `@capacitor/push-notifications`, `@capacitor/app`,
and `@capawesome/capacitor-badge` to no-op stubs in `src/mocks/` so web builds compile without
native plugins; runtime code also guards with `Capacitor.isNativePlatform()`. The real plugin
dependencies live in `src-capacitor/package.json`.

## Security model (current state)

RLS is enabled on all tables but intentionally loose during development: SELECT/INSERT (and
often UPDATE) on ideas/bugs/tbi/messages/profiles is allowed for **any authenticated user**.
True project scoping exists only on `projects` (members see their projects) and
`project_members` (owners manage, members view), via the `is_member`/`is_owner` SQL helpers.
Deletes are restricted to creators (plus members for TBI). Storage accesses use short-lived
signed URLs (1 h). Do not rely on RLS for project data isolation in the current code.

**This is the dev-phase state and is being replaced.** The target model — organizations as the
tenant boundary, org roles (owner/admin/member/guest), and a single `can_access_project()`
chokepoint for every content policy — is specified in `docs/multi-tenancy.md`, with the
migration sequenced in `BACKLOG.md` § B.

## Related docs

- Database details: `supabase/schema.sql` (authoritative), `docs/database.md`
- Workflows: `docs/workflows.md`
- Dev setup: `docs/development.md`
- Session knowledge base: `CLAUDE.md`
