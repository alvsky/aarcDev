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

## Items (ideas, bugs, tasks)

All three live in one `items` table — see `docs/item-model.md` for why.

1. Anyone in the project creates an item: `kind` is `idea`, `bug` or `task`, optional
   screenshot. A task is born `accepted` (nobody proposes work they are already doing);
   ideas and bugs start at `new`.
2. **Accept** (`itemsStore.accept`): `stage → accepted`, records `accepted_by`/`accepted_at`.
   That is the whole promotion — one column, same row, same thread.
3. **Reject** (`reject`) and **Reopen** (`reopen`) replace the old demote. Nothing is deleted,
   so no conversation is ever lost.
4. **Done** (`markDone`) records `completed_by`/`completed_at`; `markUndone` returns the item
   to `accepted` if it was ever accepted, otherwise to `new`.
5. `assign(id, userId)` sets `assignee_id`.

Stage transitions must go through these actions rather than a raw `updateItem`, because the
`*_by`/`*_at` columns are written alongside the stage.

Accepting is **optional for bugs**: a small fix can go `new → done` without ever reaching the
board. For an idea, acceptance is a real decision and the step carries meaning.

### Which tab shows what

| Tab   | Filter                                                       |
| ----- | ------------------------------------------------------------ |
| Ideas | `kind='idea'`, not in an active stage                        |
| Bugs  | `kind='bug'`, every stage                                    |
| TBI   | active stages (`accepted`/`in_progress`/`testing`), any kind |

Tabs are saved filters, not containers, so an accepted bug appears in both Bugs and TBI. It
carries a badge only on TBI — see the badge rule in `docs/item-model.md`.

Store getters return each tab's whole domain; hiding closed items is done by the list panel,
which never hides an item that is watched or has unread messages.

## Chat

- **Channels:** every project has `main` and `offtopic` (hardcoded tab set in ChatPage).
- **Item threads:** each item has exactly one thread (`messages.item_id` set, `channel` null).
  One item, one conversation — accepting or rejecting never moves or splits it.
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

1. **Thread reads** (`message_reads`): a `last_read_at` watermark per thread/channel, written
   by a plain `.upsert()` when a channel or thread is opened. A message is unread if newer
   than the watermark (or no watermark exists) and not authored by the user.
2. **Item "NEW" flags** (`item_user_state.read_at`): an item is `is_new` until the user opens
   it (`itemsStore.markRead`), unless they created it or it is done/rejected.

`notificationsStore.fetchUnread()` recomputes everything client-side and produces per project:
`total`, per-channel counts, per-item counts, and `newIdeas`/`newBugs`/`newTbi` tab counts
(thread unread counts fold into the tab counts but are not double-counted in `total`). It runs
on project open, after every realtime event, and after each markRead.

**Which tab a count lands on is decided by `stage`, not `kind`** — an accepted bug counts on
TBI, not Bugs. Two rules, deliberately different: a _new item_ in a terminal stage counts
nowhere, but an unread _message_ on a closed item is still real and is attributed to the tab
where that item can be found.

Per-member **`badge_enabled`** (project_members) turns off both unread counting and push for
that project.

Badge chain: `fetchUnread()` → `syncBadge()` → native app-icon badge (`@capawesome`
plugin). On app resume the badge is cleared and recomputed (`App.vue`).

## Push notifications

1. Message INSERT fires the `push-on-message` DB webhook → Edge Function.
2. Function targets project members with `badge_enabled = true`, excluding the author; reads
   their `push_tokens`; sends FCM v1 messages (title = project name, body =
   `Author: first 80 chars` or "📎 Screenshot").
3. Item INSERT fires the same Edge Function via the `push-on-item` webhook; it branches on
   `payload.table` and picks the category from `kind`/`stage`, matching the badge rule.
4. Token registration on app start (`usePush().init()`):
   - **Android:** standard Capacitor `registration` listener → upsert `push_tokens`.
   - **iOS:** token arrives natively (`AppDelegate.swift`, FirebaseMessaging) and is bridged
     to JS via `localStorage.setItem('fcmToken', …)`; `usePush` polls localStorage up to 30 s.

## Realtime wiring (per project screen)

`ProjectPage.vue` on mount: parallel-fetch items, unread and main-channel messages, then
subscribe:

- project-filtered channel (via `useRealtime`): INSERT/UPDATE/DELETE on `messages` and
  `items` → the store's `handleIncoming` + `fetchUnread()`
- unfiltered channel for message UPDATEs (edits)
- unfiltered channel for `message_reactions` (refetches reactions for the affected message)

All channels are removed on unmount. Note the realtime payloads lack the client-side merged
fields (`profiles`, `message_count`, `is_new`) — `handleIncoming` merges raw rows in.
