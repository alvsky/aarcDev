# aarcDev — Business Workflows

How the app's domain flows work, end to end. Store actions referenced live in `src/stores/`.

## Projects & membership

- **Create project** (`projectsStore.createProject`): insert into `projects` (no `.select()`
  on the insert — RLS workaround), re-select the creator's newest project, then insert the
  creator into `project_members` as `owner`. No DB trigger does this — keep the two-step.
- **Add member** (`addMember`): looks up `profiles` by **email**, inserts a `member` row.
  There is no invitation flow — the user must already have an account.
- **Roles:** `owner` can manage members (RLS-enforced for DELETE) and is checked by
  `is_owner()`. Everything else is by convention.
- **Delete account** (`authStore.deleteAccount`): first checks client-side whether the user is
  the **sole owner** of any project — if so, throws `{ type: 'sole_owner', projects: [names] }`
  and the UI tells them to transfer ownership or delete those projects first. Otherwise calls
  the `delete_own_account()` RPC (deletes `auth.users`, cascades everywhere).

## Ideas

1. Anyone in the project creates an idea (title, description, optional screenshot).
2. Ideas list splits into **active** (`promoted = false`) and **promoted**.
3. **Promote to TBI** (`ideasStore.promoteToTbi`):
   - creates a `tbi_items` row: `source_type: 'idea'`, `idea_id` back-link, copies
     title/description, sets `promoted_at`
   - sets `idea.promoted = true` — the idea row **remains** (its thread stays reachable)
4. **Demote** (`demoteFromTbi`): deletes the TBI row, resets `idea.promoted = false`.

## Bugs

1. Bug is reported with priority (`low`/`med`/`high`) and optional screenshot.
2. Lifecycle (plain-text status, frontend convention): `open` → `confirmed` → `promoted`,
   or `closed` at any point.
3. **Promote to TBI** (`bugsStore.promoteToBug`): creates a TBI row (`source_type: 'bug'`,
   `bug_id` back-link, **copies priority**), sets bug `status: 'promoted'` + `promoted_at`.
   The bug row remains. There is no demote for bugs in the UI.

## TBI (To Be Implemented)

- Items arrive three ways: manually (`source_type: 'manual'`), promoted from an idea, or from
  a bug. Back-links (`idea_id`/`bug_id`) are `SET NULL` — a TBI item survives source deletion.
- `assignee_id` assigns a member (`assignUser`).
- **Done:** `markDone` sets `status: 'done'` + `completed_at`; `markUndone` reverts to `tbi`.
- A TBI card's message count = its own thread **+** linked idea's thread **+** linked bug's
  thread (summed from the `thread_message_counts` view).

## Chat

- **Channels:** every project has `main` and `offtopic` (hardcoded tab set in ChatPage).
- **Item threads:** each idea/bug/TBI item has a thread (message rows with that item's id set
  and `channel` null).
- **Send** (`chatStore.sendMessage`): insert only — the store does **not** refetch; the
  realtime INSERT event echoes the message back into `threads`. Don't "fix" this by refetching.
- **Edit:** author only (RLS); sets `edited_at`. Delivered to others via an UPDATE
  subscription.
- **Delete:** author only; also removes the attachment object from storage (client-side).
- **Reactions:** toggle per (message, user, emoji); unique constraint enforces one of each.
  Reaction changes arrive via a separate realtime subscription on `message_reactions`.
- **Attachments/screenshots:** images only; compressed client-side (canvas → JPEG ≤1920px)
  then uploaded to `chat-attachments` at `${userId}/${timestamp}.jpg`. Display always goes
  through 1-hour signed URLs.

## Unread & notifications

Two independent mechanisms, both per-user:

1. **Thread reads** (`message_reads`): a `last_read_at` watermark per thread/channel. Updated
   via the `upsert_message_read` RPC when ChatPage loads a channel or the user scrolls to
   bottom. A message is unread if newer than the watermark (or no watermark exists) and not
   authored by the user.
2. **Item "NEW" flags** (`item_reads`): an idea/bug/TBI is `is_new` until the user opens it
   (`markItemRead`), unless they created it or it's done/closed.

`notificationsStore.fetchUnread()` recomputes everything client-side and produces per project:
`total`, per-channel counts, per-thread counts, and `newIdeas`/`newBugs`/`newTbi` tab counts
(thread unread counts fold into the tab counts but are not double-counted in `total`). It runs
on project open, after every realtime event, and after each markRead.

Per-member **`badge_enabled`** (project_members) turns off both unread counting and push for
that project.

Badge chain: `fetchUnread()` → `syncBadge()` → native app-icon badge (`@capawesome`
plugin). On app resume the badge is cleared and recomputed (`App.vue`).

## Push notifications

1. Message INSERT fires the `push-on-message` DB webhook → Edge Function.
2. Function targets project members with `badge_enabled = true`, excluding the author; reads
   their `push_tokens`; sends FCM v1 messages (title = project name, body =
   `Author: first 80 chars` or "📎 Screenshot").
3. Only **messages** trigger push — new ideas/bugs/TBI items do not.
4. Token registration on app start (`usePush().init()`):
   - **Android:** standard Capacitor `registration` listener → upsert `push_tokens`.
   - **iOS:** token arrives natively (`AppDelegate.swift`, FirebaseMessaging) and is bridged
     to JS via `localStorage.setItem('fcmToken', …)`; `usePush` polls localStorage up to 30 s.

## Realtime wiring (per project screen)

`ProjectPage.vue` on mount: parallel-fetch ideas/bugs/tbi/unread/main-channel messages, then
subscribe:

- project-filtered channel (via `useRealtime`): INSERT/UPDATE/DELETE on
  messages/ideas/bugs/tbi_items → each store's `handleIncoming` + `fetchUnread()`
- unfiltered channel for message UPDATEs (edits)
- unfiltered channel for `message_reactions` (refetches reactions for the affected message)

All channels are removed on unmount. Note the realtime payloads lack the client-side merged
fields (`profiles`, `message_count`, `is_new`) — `handleIncoming` merges raw rows in.
