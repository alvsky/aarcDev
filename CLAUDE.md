# CLAUDE.md — aarcDev

Mobile-first collaboration app for small dev teams. Each **project** has four tabs: **Chat**
(channels `main`+`offtopic`), **Bugs**, **Ideas**, **TBI** ("To Be Implemented" backlog).
Ideas/bugs promote into TBI items; every item has its own chat thread. Unread counts, app-icon
badges, FCM push. UI/comments partly Croatian (i18n: `en` default, `hr` fallback).

Stack: Quasar 2 (app-vite) + Vue 3 + Pinia 3 + vue-router 5 (hash) + Supabase JS v2 +
Capacitor 8 (iOS/Android). **pnpm**. No tests.

# Important

Before making changes, always read:

- AI_RULES.md

## Detailed docs — read the relevant one before working in that area

| Doc                    | Contents                                                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------- |
| `docs/architecture.md` | Layers, data-flow patterns, routing quirk, push pipeline, security model                           |
| `docs/database.md`     | All tables/relationships/RLS matrix/storage; schema source = `supabase/schema.sql` (authoritative) |
| `docs/workflows.md`    | Promote/demote flows, chat rules, unread/notification mechanics, realtime wiring                   |
| `docs/development.md`  | Setup, `.env`, scripts, Capacitor mocks, iOS FCM bridge, Supabase ops, conventions                 |

## Critical invariants (violating these breaks the app)

1. **Manual profile joins.** `created_by`/`author_id`/`assignee_id` FKs reference
   `auth.users`, NOT `profiles` — PostgREST embeds (`profiles(...)`) fail. Fetch rows, fetch
   profiles by id list, merge client-side. Every store does this.
2. **Realtime is the write-echo.** After `chatStore.sendMessage`, do NOT refetch — the
   realtime INSERT populates the thread (dedup by id in `handleIncoming`).
3. **`message_reads` writes only via the `upsert_message_read` RPC** — a COALESCE functional
   unique index makes plain `.upsert()` fail to conflict.
4. **Single `messages` table.** Thread = exactly one of `idea_id`/`bug_id`/`tbi_id` set
   (`channel` null), or all null + `channel`. Chat store keys: `${projectId}:idea:${id}` etc.
   or `${projectId}:${channel}`.
5. **RLS is permissive** — any authenticated user can read ideas/bugs/tbi/messages/profiles
   across projects; scoping is client-side. Don't assume isolation; don't silently "fix".
6. **Multi-project store state** — merge with
   `[...state.filter(x => x.project_id !== pid), ...mapped]`, never blind-replace.
7. All Supabase access goes through Pinia stores (`src/stores/`), never components directly.
   Stores with a `persist: [...]` option are hydrated per-user from IndexedDB (localforage,
   `src/stores/persist-plugin.js`) — hydration fills only empty fields; fetch actions
   early-return offline to keep cached state; chat has an `outbox` queue with optimistic
   `pending` messages flushed on reconnect/resume/login (see docs/offline-first.md).
8. Status/priority/role columns are plain text, **no CHECK constraints** — frontend
   convention only (bug: open→confirmed→promoted/closed; tbi: tbi|done; priority low|med|high).

## Quick facts

- No custom backend: stores → supabase-js → Supabase (Auth/Postgres/Realtime/Storage +
  `push-on-message` Edge Function fired by DB webhook on message INSERT → FCM v1).
- `/project/:id` (ProjectPage.vue) ignores its declared child routes — renders q-tabs +
  keep-alive panels passing `projectId` as a **prop**; tabs don't change URL.
- Each page owns its own `q-layout`; MainLayout is a bare passthrough. The top bar is the
  shared `components/shared/AppHeader.vue` (props `title`/`back`/`backTo`/`settings`, slots
  `#left`/`#actions`/`#tabs`) — it bakes in safe-area-inset-top and the offline strip
  (`useNetwork`). Don't hand-roll `q-toolbar` per page; use AppHeader.
- `notificationsStore.fetchUnread()` recomputes all unread client-side after nearly every
  event; single source for all badges. Known bottleneck.
- `project_members.badge_enabled` gates both unread counting and push, per user per project.
- Storage: one private bucket `chat-attachments` (`${userId}/${timestamp}.jpg`, client-side
  JPEG compression, 1-h signed URLs).
- iOS FCM token arrives via AppDelegate.swift → `localStorage['fcmToken']` polling bridge
  (Android uses the normal Capacitor listener). Web builds use no-op mocks aliased in
  quasar.config.js **only when `!ctx.mode.capacitor`** — native builds must get the real
  plugins (they resolve from `src-capacitor/node_modules` via Quasar's modeDeps).
- `.env` (gitignored): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`; project ref
  `uwtmnbliuuoqkmwjwzid` also hardcoded in the schema's webhook trigger.
- Use `maybeSingle()` when a row may not exist. Imports use `src/...` alias (not `@/`).
- Lint: `npm run lint` (writes) / `lint:check`.

## Known TODOs

- Dead files: ChatPage-copy.vue, LoginPage8.vue (empty), BugCard-copy.vue, app-copy.scss,
  router/index-copy.js, example-store.js, IndexPage/SecondPage.vue, src/i18n/en-US/.
- Legacy `bug_reads`/`idea_reads` tables unused; `item_reads` has no FK (orphans on delete).
- Debug console.logs in stores/pages; unfiltered realtime channels for message
  updates/reactions; unused nested child routes; RLS tightening open; `fetchUnread()` won't
  scale; Capacitor appName mismatch (`aarc` vs `aarcDev`); only one git commit exists.
