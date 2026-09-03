# CLAUDE.md — aarcDev

Mobile-first collaboration app for small dev teams. Each **project** has four tabs: **Chat**
(channels `main`+`offtopic`), **Bugs**, **Ideas**, **TBI** ("To Be Implemented" backlog).
Those three item tabs are **filtered views over one `items` table** — accepting an idea moves
it to the TBI board by changing one column, not by creating a second row. Every item has one
chat thread. Unread counts, app-icon badges, FCM push. UI/comments partly Croatian (i18n: `en`
default, `hr` fallback).

Stack: Quasar 2 (app-vite) + Vue 3 + Pinia 3 + vue-router 5 (history mode since 2026-08-12,
was hash) + Supabase JS v2 + Capacitor 8 (iOS/Android). **pnpm**. No tests.

# Important

Before making changes, always read:

- AI_RULES.md

## Detailed docs — read the relevant one before working in that area

| Doc                     | Contents                                                                                           |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| `docs/architecture.md`  | Layers, data-flow patterns, routing quirk, push pipeline, security model                           |
| `docs/database.md`      | All tables/relationships/RLS matrix/storage; schema source = `supabase/schema.sql` (authoritative) |
| `docs/workflows.md`     | Promote/demote flows, chat rules, unread/notification mechanics, realtime wiring                   |
| `docs/development.md`   | Setup, `.env`, scripts, Capacitor mocks, iOS FCM bridge, Supabase ops, conventions                 |
| `docs/multi-tenancy.md` | **Target** org/project tenancy + role model, RLS chokepoint, rationale, rejected alternatives      |

## Critical invariants (violating these breaks the app)

1. **Manual profile joins.** `created_by`/`author_id`/`assignee_id` FKs reference
   `auth.users`, NOT `profiles` — PostgREST embeds (`profiles(...)`) fail. Fetch rows, fetch
   profiles by id list, merge client-side. Every store does this.
2. **Realtime is the write-echo.** After `chatStore.sendMessage`, do NOT refetch — the
   realtime INSERT populates the thread (dedup by id in `handleIncoming`).
3. **One `items` table** for ideas, bugs and tasks — `kind` (idea|bug|task) never changes,
   `stage` (new|confirmed|accepted|in_progress|testing|done|rejected) does. Tabs are saved
   **filters**, not containers, so one item may show in two tabs but counts toward exactly one
   badge. Stage transitions go through store actions (`accept`/`reject`/`markDone`/`reopen`),
   never a raw `update` — the `accepted_by`/`rejected_by`/`completed_by` columns depend on it.
   See `docs/item-model.md`.
4. **Single `messages` table.** Thread = `item_id` set (`channel` null), or `item_id` null +
   `channel`. Chat store keys: `${projectId}:item:${id}` or `${projectId}:${channel}`.
5. **RLS is permissive — but this is now legacy, not the goal.** Any authenticated user can
   currently read ideas/bugs/tbi/messages/profiles across projects; scoping is client-side, so
   **never rely on RLS for isolation in existing code**. As of 2026-08-08 the app is heading to
   public distribution and the target model (orgs as tenants, roles, one `can_access_project`
   chokepoint) is specified in `docs/multi-tenancy.md`, sequenced in BACKLOG § B. Tighten
   policies _deliberately, as that migration_, never as a silent side effect of other work.
6. **Multi-project store state** — merge with
   `[...state.filter(x => x.project_id !== pid), ...mapped]`, never blind-replace.
7. All Supabase access goes through Pinia stores (`src/stores/`), never components directly.
   Stores with a `persist: [...]` option are hydrated per-user from IndexedDB (localforage,
   `src/stores/persist-plugin.js`) — hydration fills only empty fields; fetch actions
   early-return offline to keep cached state; chat has an `outbox` queue with optimistic
   `pending` messages flushed on reconnect/resume/login (see docs/offline-first.md).
8. **`items` constrains its own vocabulary** (`kind`/`stage`/`priority` have CHECK
   constraints); everything else — `project_members.role`, `push_tokens.platform` — is still
   plain text by frontend convention only.

## Quick facts

- **Versioning**: iOS is the source of truth (`MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` in `src-capacitor/ios/App/App.xcodeproj/project.pbxproj`).
  Android (`versionCode`/`versionName` in `src-capacitor/android/app/build.gradle`),
  root `package.json` `version`, and `CHANGELOG.md` must be bumped to match — they had
  already drifted once (iOS build 23 vs Android 1 vs package.json 0.0.1, fixed 2026-08-12).
  **`CHANGELOG.md` is not what ships** — the in-app changelog page reads a hardcoded
  `entries` array in `src/pages/ChangelogPage.vue`, and the version/build shown in Settings
  → About come from hardcoded `appVersion`/`appBuild` in `src/pages/AboutPage.vue`. Bumping
  the version files and `CHANGELOG.md` without also updating these two leaves the app itself
  reporting the old build after an upgrade — happened 2026-09-03 (stuck reporting build 30
  through build 33).
- No custom backend: stores → supabase-js → Supabase (Auth/Postgres/Realtime/Storage +
  `push-on-message` Edge Function fired by DB webhook on message INSERT → FCM v1).
- `/project/:id/:tab(chat|bugs|ideas|tbi)?` (ProjectPage.vue) has no rendered child routes —
  it draws q-tabs + keep-alive panels itself, passing `projectId` as a **prop**; the active
  tab lives in `route.params.tab` (writable computed, `router.replace`), not local state
  (since I1, 2026-08-11 — used to be invisible to the URL entirely).
- Each page owns its own `q-layout`; MainLayout is a bare passthrough. The top bar is the
  shared `components/shared/AppHeader.vue` (props `title`/`back`/`backTo`/`settings`, slots
  `#left`/`#actions`/`#tabs`) — it bakes in safe-area-inset-top and the offline strip
  (`useNetwork`). Don't hand-roll `q-toolbar` per page; use AppHeader.
- `notificationsStore.fetchUnread()` recomputes all unread client-side after nearly every
  event; single source for all badges. Known bottleneck.
- `project_members.badge_enabled` gates both unread counting and push, per user per project;
  `notif_messages`/`notif_ideas`/`notif_bugs`/`notif_tbi` narrow it per category.
- Push fires on message INSERT **and** item INSERT (two DB webhooks → the same
  `push-on-message` Edge Function, which branches on `payload.table`).
- Storage: two private buckets (B16) — `chat-attachments` (`${projectId}/${userId}/${uuid}.jpg`,
  RLS via `can_access_project`) and `avatars` (`${userId}/${uuid}.jpg`, RLS via
  `can_see_profile`). Client-side JPEG compression, 1-h signed URLs. Policies are in
  `supabase/migrations/20260814100000_storage_policies.sql`, not just the dashboard.
- iOS FCM token arrives via AppDelegate.swift → `localStorage['fcmToken']` polling bridge
  (Android uses the normal Capacitor listener). Web builds use no-op mocks aliased in
  quasar.config.js **only when `!ctx.mode.capacitor`** — native builds must get the real
  plugins (they resolve from `src-capacitor/node_modules` via Quasar's modeDeps).
- `.env` (gitignored): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`; project ref
  `uwtmnbliuuoqkmwjwzid` also hardcoded in the schema's webhook trigger.
- Use `maybeSingle()` when a row may not exist. Imports use `src/...` alias (not `@/`).
- Lint: `npm run lint` (writes) / `lint:check`.

## Known TODOs

- Dead files: `LoginPage8.vue` (empty) is the last one.
- Debug console.logs in stores/pages; unfiltered realtime channels for message
  updates/reactions; unused nested child routes; `fetchUnread()` won't scale; Capacitor
  appName mismatch (`aarc` vs `aarcDev`).
- **Android push works** — confirmed end-to-end 2026-08-13 on an emulator (Pixel_8a_API_35,
  Play Store image): `google-services.json` added, POST_NOTIFICATIONS permission granted,
  real FCM token registered to `push_tokens`, a chat message triggered the DB webhook →
  `push-on-message` edge function → FCM → an actual system notification appeared. Still
  needed: restrict the Android API key by package name + SHA-1 in Google Cloud Console
  (manual, Console access required). See BACKLOG L5/L6.
- **Multi-tenancy migration is the current priority** — see `docs/multi-tenancy.md` and
  BACKLOG § B. Until it lands, RLS gives no isolation.
