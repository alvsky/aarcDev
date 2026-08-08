# aarcDev — Item model

> **Status: target model, not yet implemented.** The live schema still has three separate
> tables (`ideas`, `bugs`, `tbi_items`). Decided 2026-08-08. Once implemented,
> `supabase/schema.sql` is authoritative for the _what_ — this file keeps the _why_.

## The problem it replaces

Today one logical thing can have **two rows**: an idea and, once promoted, a `tbi_items` row
linked back to it. Each row owns a separate message thread. That single fact produced seven
distinct defects:

1. A promoted idea is hidden from the Ideas list, but its thread is still counted → a badge
   that cannot be reached or cleared (the bug that triggered this redesign)
2. `TbiPage` has to merge two threads by hand (`combinedMessages`)
3. `thread_message_counts` sums three separate counters for one card
4. `ON DELETE CASCADE` destroys the TBI conversation on demote
5. `markRead` must hit several threads before a badge disappears
6. `item_reads` on the idea does not carry over to the TBI
7. An item hidden from a list still counts toward that list's badge

These are not seven bugs. They are one design decision, seen seven times.

## One table, two axes

**`kind`** — what the item is. Never changes.

|        |                                                        |
| ------ | ------------------------------------------------------ |
| `idea` | a proposal                                             |
| `bug`  | a defect report                                        |
| `task` | work entered directly (today's `source_type='manual'`) |

**`stage`** — where it is in the flow. This is what changes.

|             |                                                         |
| ----------- | ------------------------------------------------------- |
| `new`       | filed, not yet triaged                                  |
| `confirmed` | acknowledged, not yet scheduled                         |
| `accepted`  | scheduled for implementation — this is what "TBI" means |
| `done`      | completed                                               |
| `rejected`  | decided against                                         |

**Promotion is `stage: new → accepted`.** One update, one row, one thread. Nothing is copied,
moved, or deleted — which is why defects 1–7 stop being possible rather than being fixed.

`kind` and `stage` carry `CHECK` constraints. This deliberately breaks with the existing
"plain text, no constraints" convention (CLAUDE.md invariant 8): the old tables keep that
convention, the new one does not. A new vocabulary is the cheapest possible moment to
constrain it.

## Tabs are views, not containers

An item is not "in" a tab. Each tab is a saved filter over one table, so the same item may
legitimately appear in two of them.

| Tab       | Filter                                   | Role                                 |
| --------- | ---------------------------------------- | ------------------------------------ |
| **Bugs**  | `kind='bug'` — **all stages**            | registry — the full defect history   |
| **Ideas** | `kind='idea'` + stage `new`, `confirmed` | funnel — awaiting a decision         |
| **TBI**   | `stage='accepted'` — **any kind**        | work board — what is being built now |

The asymmetry is intentional. A registry wants history ("has this been reported before?"); a
funnel wants only what still needs a decision. Both tabs offer filters to reveal the rest.

Consequence: **promotion is optional for bugs.** A small fix goes `new → done` without ever
being accepted. Only scheduled work reaches the board. Ideas keep a meaningful promotion step,
because for a proposal, acceptance is a real decision. A bug is already work; a bug report that
must be "promoted" before it counts is a step carrying no information.

## One item, one badge

Visibility and counting are separate. An item may appear in two tabs but must never be counted
twice.

> An item counts toward **exactly one** tab badge — the tab where it needs attention, chosen by
> `stage`, not by `kind`.

- stage `new` / `confirmed` → counts on Bugs or Ideas (per `kind`)
- stage `accepted` → counts on TBI **only**, whatever the `kind`
- stage `done` / `rejected` → counts nowhere

So an accepted bug is still _visible_ under Bugs, but carries no badge there.

## Authorship

Today `tbi_items.created_by` means "author" for manual items and "promoter" for promoted ones —
one column, two meanings. Split into explicit pairs:

| Column pair                     | Meaning                                                 |
| ------------------------------- | ------------------------------------------------------- |
| `created_by` / `created_at`     | the original author or reporter — **never overwritten** |
| `accepted_by` / `accepted_at`   | who scheduled it for implementation                     |
| `rejected_by` / `rejected_at`   | who decided against it                                  |
| `completed_by` / `completed_at` | who closed it out                                       |

`priority` (`low`/`med`/`high`) now applies to every kind, not only bugs.

## Per-user state

```
item_user_state (user_id, item_id, read_at, watching_at)
```

Replaces `item_reads` and carries the new **"Pratim"** marker (`watching_at IS NOT NULL`).
A timestamp rather than a boolean: same cost, and "since when" becomes sortable.

The marker is **personal** — each user has their own set, invisible to others — **on/off**, and
currently **visual only**: it drives highlighting and a filter, not notifications. The name
leaves room to add notifications later without a rename; until then the UI should describe it
as "set aside for easier tracking" rather than implying alerts.

Shared importance is already covered by `priority`; the marker is the personal layer on top.

This table also fixes BACKLOG C5 — `item_id` finally gets a real foreign key, so rows no longer
orphan when an item is deleted.

## Rejected and deferred

- **Demote (TBI → idea)** — removed. It conflated three needs: undoing a mistaken promotion,
  deciding against something, and parking it. These are now `stage` changes: back to `new`,
  `rejected`, or `confirmed`. Nothing is deleted, so nothing is lost.
- **System messages in the thread** for stage changes — rejected in favour of the
  `accepted_by`/`rejected_by` columns. Cheaper, and keeps threads to human conversation.
- **Full change history** — the columns above record only the _latest_ transition. Accept →
  reject → accept keeps the last. A proper `item_events` table is the answer if this ever
  matters; deliberately deferred.
- **Per-user priority levels** (personal important/normal/low) — rejected. `priority` already
  provides degrees; a personal on/off marker on top is enough.
- **Merging `messages`' three FKs is a separate step** — see BACKLOG; it also removes the
  COALESCE unique index that forces `message_reads` through an RPC (invariant 3).

## Related

- Tenancy and access rules: `docs/multi-tenancy.md`
- Current (pre-migration) tables: `docs/database.md`
- Migration steps: `BACKLOG.md`
- Schema source of truth: `supabase/schema.sql`
