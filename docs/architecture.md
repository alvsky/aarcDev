# aarcDev — Architecture

aarcDev is a mobile-first collaboration app for small development teams. A **project** is the
central unit; inside a project the team works across four tabs: **Chat** (channels `main` and
`offtopic`), **Bugs**, **Ideas**, and **TBI** ("To Be Implemented" — the work backlog). Ideas
and bugs can be promoted into TBI items, and every item carries its own chat thread.

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
handful of SQL functions (`is_member`, `is_owner`, `upsert_message_read`,
`delete_own_account`, `handle_new_user`), and one Edge Function for push notifications.

## Layers

| Layer | Location | Role |
|---|---|---|
| Pages | `src/pages/` | Route targets and project tab panels |
| Components | `src/components/{chat,bugs,ideas,tbi,shared}/` | Presentational + dialogs |
| Stores | `src/stores/` | All data access, business rules, realtime merge logic |
| Composables | `src/composables/` | Cross-cutting: realtime wiring, push, badge, image upload, date format |
| Boot | `src/boot/` | Supabase client singleton, vue-i18n (en default, hr fallback) |
| Native shell | `src-capacitor/` | Capacitor 8 iOS/Android projects, Firebase config |

## Key data-flow patterns

### Manual profile joins

`created_by` / `author_id` / `assignee_id` foreign keys reference `auth.users`, **not**
`public.profiles`. PostgREST therefore cannot embed profiles (`profiles(...)` fails). Every
store follows the same pattern: fetch domain rows → collect user ids → fetch `profiles` by id
list → merge client-side into a `profiles` (and `assignee`) property on each row. Any new
query that needs author names must repeat this pattern.

### Realtime as the write-echo

`useRealtime(projectId, handlers)` opens one Supabase channel per project subscribing to
INSERT/UPDATE/DELETE on `messages`, `ideas`, `bugs`, and `tbi_items`, filtered by
`project_id`. Each store exposes `handleIncoming({ event, payload })` that merges the event
into local state (deduplicating by id).

Consequence: after a write such as `chatStore.sendMessage`, the store deliberately does
**not** refetch — the realtime INSERT event is what appends the message locally. ProjectPage
additionally opens two unfiltered channels: message UPDATEs (edits) and `message_reactions`.
`messages` has `REPLICA IDENTITY FULL` so DELETE events carry the old row.

### Chat threading model

A single `messages` table serves every conversation. Thread identity is determined by which
column is set:

- `idea_id` / `bug_id` / `tbi_id` set (exactly one) → item thread, `channel` is null
- all three null → project channel chat, `channel` = `main` or `offtopic`

The chat store mirrors this with a `threads` dictionary keyed by
`${projectId}:idea:${id}` / `:bug:` / `:tbi:` or `${projectId}:${channel}`
(`chatStore.threadKey()`).

### Unread tracking (two mechanisms)

1. **Per-thread message reads** — `message_reads` rows store `last_read_at` per user per
   thread/channel. Written only via the `upsert_message_read` RPC (a COALESCE functional
   unique index makes plain upserts fail to conflict). Marked when ChatPage loads a channel or
   the user scrolls to bottom.
2. **Per-item "NEW" flags** — `item_reads` (user, item, type) marks an idea/bug/TBI as seen;
   stores compute `is_new` from it.

`notificationsStore.fetchUnread()` recomputes the whole unread picture **client-side**: it
fetches all messages authored by others, all the user's reads, and all open items, honors the
per-member `badge_enabled` flag, and produces per-project totals plus per-thread and per-tab
counts. It runs after nearly every realtime event and is the single source for tab badges,
project-card badges, and the native app-icon badge. This is a known scaling bottleneck.

## Routing and the project screen

Hash-mode router (`src/router/index.js`). A global guard lazily runs `auth.init()` and
redirects unauthenticated users to `/login`.

`/project/:id` renders `ProjectPage.vue`, which does **not** use nested routes even though
child routes are declared: it renders its own `q-tabs` + keep-alive `q-tab-panels`, mounting
ChatPage/IdeasPage/BugsPage/TbiPage as plain components with a `projectId` prop. Tab switches
do not change the URL. ProjectPage is also where realtime channels are set up and torn down.

## Promotion workflows

- **Idea → TBI:** creates a `tbi_items` row (`source_type: 'idea'`, back-link `idea_id`) and
  sets `idea.promoted = true`; the idea remains, listed as promoted. Demoting deletes the TBI
  row and resets the flag.
- **Bug → TBI:** creates a TBI row (`source_type: 'bug'`, copies priority) and sets the bug's
  status to `promoted`. Bug lifecycle: `open → confirmed → promoted / closed`.
- TBI items complete via `status: 'done'` + `completed_at`. A TBI card's message count
  aggregates its own thread **plus** the linked idea's and bug's threads
  (via the `thread_message_counts` view).

## Push notification pipeline

```
messages INSERT
  └─ DB webhook trigger ("push-on-message")
       └─ Edge Function supabase/functions/push-on-message/
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
signed URLs (1 h). Tightening RLS to project scope is an open TODO — do not rely on RLS for
project data isolation.

## Related docs

- Database details: `supabase/schema.sql` (authoritative), `docs/database.md`
- Workflows: `docs/workflows.md`
- Dev setup: `docs/development.md`
- Session knowledge base: `CLAUDE.md`
