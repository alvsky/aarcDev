# aarcDev — Development

## Prerequisites

- Node ≥ 22.12 (see `engines` in package.json), **pnpm**
- Quasar CLI (`@quasar/app-vite` is a devDependency; `npx quasar` works)
- For native builds: Xcode (iOS) / Android Studio, CocoaPods not required (iOS uses SPM)
- Supabase CLI for edge-function work

## Setup

```bash
pnpm install          # runs "quasar prepare" via postinstall
```

Create `.env` in the repo root (gitignored, not committed):

```
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
```

The live project ref is `uwtmnbliuuoqkmwjwzid` (also hardcoded in the `push-on-message`
webhook trigger inside `supabase/schema.sql`).

## Scripts

```bash
quasar dev                          # web dev server (HMR)
quasar dev -m capacitor -T ios      # native dev
quasar dev -m capacitor -T android
quasar build                        # production web build
quasar build -m capacitor -T ios    # native build (then archive in Xcode / Android Studio)

npm run lint          # prettier --write + eslint --fix (rewrites files)
npm run lint:check    # check-only variant
```

There is no test suite.

## Web vs native: the Capacitor mocks

`quasar.config.js` → `build.extendViteConf` aliases these **only for web builds**
(`!ctx.mode.capacitor`):

| Package                         | Aliased to                     |
| ------------------------------- | ------------------------------ |
| `@capacitor/push-notifications` | `src/mocks/capacitor-push.js`  |
| `@capacitor/app`                | `src/mocks/capacitor-app.js`   |
| `@capawesome/capacitor-badge`   | `src/mocks/capacitor-badge.js` |

The mocks are no-ops (permissions return `denied`), letting web builds compile without the
native plugins. **Native builds must never get the mocks** — that silently kills push and
badge (permission never requested, app missing from iOS Settings → Notifications; this
happened once, fixed 2026-08-05). In capacitor mode the real plugins resolve from
`src-capacitor/node_modules` (Quasar `modeDeps`) — install Capacitor plugins in
`src-capacitor/`, not the root. If you add one, decide whether the web build needs a mock.

Also in `extendViteConf`: the `src` → `/src` alias — imports use `src/...` paths, not `@/`.

## Native specifics

- appId `com.vitka.collabapp` (note: `src-capacitor/capacitor.config.js` says appName `aarc`,
  quasar.config says `aarcDev` — known mismatch).
- **iOS:** Firebase via `GoogleService-Info.plist` + Swift Package Manager (`CapApp-SPM`).
  Push entitlements in `App.entitlements`. `AppDelegate.swift` implements `MessagingDelegate`
  and bridges the FCM token to the web view through `localStorage.setItem('fcmToken', …)` —
  `usePush` polls for it. Don't remove that bridge; the standard Capacitor `registration`
  event is only used on Android.
- **Android:** standard FCM setup; token comes through the Capacitor `registration` listener.
- App-icon badge uses `@capawesome/capacitor-badge`; badge count = total unread across
  projects, cleared and recomputed on app resume (`App.vue`).

## Supabase

- **Schema changes:** apply to the Supabase project, then re-dump into
  `supabase/schema.sql` — that file is the authoritative reference (`supabase db dump`).
  `supabase/migrations/` currently holds a single full dump, not incremental migrations.
- **Edge Function** (`supabase/functions/push-on-message/`, Deno):

  ```bash
  supabase functions deploy push-on-message
  supabase secrets set FIREBASE_SERVICE_ACCOUNT='<service-account JSON>'
  ```

  It's invoked by a DB webhook trigger on `messages` INSERT (defined in schema.sql), and uses
  `SUPABASE_SERVICE_ROLE_KEY` (auto-provided) to bypass RLS.

- **Storage:** bucket `chat-attachments` must exist; access is via signed URLs, so the bucket
  stays private.
- **Realtime:** `messages` and `items` must be in the `supabase_realtime` publication.
  All of a project's subscriptions share **one channel**, so a table missing from the
  publication takes the whole channel down — the app keeps working and just stops receiving
  live updates. `useRealtime` now logs CHANNEL_ERROR instead of swallowing it.
  `messages` requires `REPLICA IDENTITY FULL` (already in schema) for DELETE payloads.

## Conventions

- All Supabase access goes through Pinia stores; components never import the client directly
  (composables may).
- Manual profile joins everywhere — user FKs point at `auth.users`, so PostgREST
  `profiles(...)` embeds fail. Fetch profiles by id list and merge.
- `message_reads` is written with a plain `.upsert()`; the RPC that used to be required is gone.
- After `sendMessage`, don't refetch — realtime echoes the insert.
- i18n: all UI strings through `vue-i18n` (`src/i18n/en.js`, `hr.js`). Some code comments are
  Croatian.
- Dark mode is a custom `dark-mode` body class styled in `src/css/app.scss` (not Quasar's
  Dark plugin); font size via the `--aarc-font-size` CSS variable.
- Prettier + ESLint (flat config) are the only gates; run `npm run lint:check` before
  committing.

## Repo state notes

- Only one git commit exists; most of the app is uncommitted working-tree changes.
- Known dead files pending cleanup: `ChatPage-copy.vue`, `LoginPage8.vue` (empty),
  `BugCard-copy.vue`, `src/css/app-copy.scss`, `src/router/index-copy.js`,
  `example-store.js`, scaffold `IndexPage.vue`/`SecondPage.vue`, `src/i18n/en-US/`.
- See `CLAUDE.md` → "Known TODOs" for the full list of open items.
