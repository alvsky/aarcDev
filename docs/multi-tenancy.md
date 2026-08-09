# aarcDev — Multi-tenancy and authorization

> **Status: target model, not yet implemented.** The live schema still has the permissive
> dev-phase policies described in `docs/database.md` § Row Level Security. This document is
> what we are migrating _to_, decided 2026-08-08 when the app moved toward public
> distribution. Once implemented, `supabase/schema.sql` is authoritative for the _what_ —
> this file keeps the _why_.

## Why this exists

The app is going out to many unrelated people and organizations. Hard requirement:
**one organization must never see anything belonging to another.** The dev-phase model
(global content reads, client-side filtering) cannot satisfy that, and no amount of frontend
work fixes it — a hostile client talks to PostgREST directly.

## The model

```
organizations   (id, name, slug, plan)
org_members     (org_id, user_id, role)      ← tenancy + permissions live here
projects        (id, org_id NOT NULL, visibility)
project_members (project_id, user_id, ...)   ← notification prefs + private-project access
items / messages           (project_id, ...)   ← see docs/item-model.md
```

`projects.visibility` is `'org'` (default — every org member) or `'private'` (only people
with an explicit `project_members` row).

## Roles

Org-level roles, granted top-down. There must always be **at least one owner** per
organization; this is enforced by a database trigger, not by the client.

| Action                             | owner | admin | member | guest |
| ---------------------------------- | :---: | :---: | :----: | :---: |
| Delete org, change plan/billing    |  ✅   |  ❌   |   ❌   |  ❌   |
| Grant or revoke `owner`            |  ✅   |  ❌   |   ❌   |  ❌   |
| Grant `admin` / `member` / `guest` |  ✅   |  ✅   |   ❌   |  ❌   |
| Invite and remove members          |  ✅   |  ✅   |   ❌   |  ❌   |
| Create a project                   |  ✅   |  ✅   |   ✅   |  ❌   |
| Delete any project in the org      |  ✅   |  ✅   |   ❌   |  ❌   |
| Access `visibility='org'` projects |  ✅   |  ✅   |   ✅   |  ❌   |
| Access explicitly granted projects |  ✅   |  ✅   |   ✅   |  ✅   |

`guest` is the external-collaborator case (agency freelancer on one client project). It costs
one branch in `can_access_project` — implement it with the rest even if the UI ships later.

`project_members.role` still exists but is now **secondary**: it only governs who manages a
private project's member list. Org role wins everywhere else.

## One chokepoint

Every content policy is exactly `USING (can_access_project(project_id))`. If the tenancy model
ever changes, one function changes — not thirty policies.

```sql
create or replace function public.can_access_project(pid uuid)
returns boolean
language sql
stable                      -- once per statement, not once per row
security definer
set search_path = public    -- closes the mutable-search_path escalation vector
as $$
  select exists (
    select 1 from projects p
    join org_members om on om.org_id = p.org_id and om.user_id = auth.uid()
    where p.id = pid
      and (
        (p.visibility = 'org' and om.role <> 'guest')
        or exists (
          select 1 from project_members pm
          where pm.project_id = p.id and pm.user_id = auth.uid()
        )
      )
  )
$$;
```

Siblings, same modifiers: `is_org_member(oid)`, `is_org_admin(oid)` (owner or admin),
`is_org_owner(oid)`.

`stable` and `set search_path` are not optional polish — without `stable` Postgres re-evaluates
the function per row inside a policy, and a mutable `search_path` on a `SECURITY DEFINER`
function is a known privilege-escalation vector. The existing `is_member`/`is_owner` have
neither.

Note the function requires org membership **and** (visibility or explicit row). A stale
`project_members` row for someone no longer in the org therefore grants nothing —
**the design fails closed.**

## Membership is never written directly

`org_members` INSERT is denied to everyone. All membership changes go through
`SECURITY DEFINER` RPCs (`accept_invitation`, `set_member_role`, `remove_member`) that check
the caller's role and the last-owner invariant. This is what closes the current hole where
`project_members` INSERT/UPDATE are `WITH CHECK (true)` — anyone can join any project and
promote themselves.

Invites are by email into an `invitations` table (token + expiry), so you can invite someone
who has no account yet.

⚠️ **Invite-by-email requires verified email at signup.** Without it, anyone can register with
someone else's address and claim their invitation. The two must ship together.

## Decisions and rationale

**Organization as the tenant boundary, not project.** Billing attaches to an org; invites are
one per org rather than one per project; and profile visibility scopes naturally to
"people I share an org with", which kills the current global email-harvesting exposure.

**Hybrid visibility rather than picking one.** "Everyone sees everything" fails agencies with
external collaborators; "explicit membership everywhere" is administrative friction for the
5-person team that is the core use case. The hybrid costs one column and four lines of SQL,
so there is no reason to force the choice.

**Access is computed, not stored.** `project_members` rows exist only for private-project
grants and customized notification prefs — not as a mirror of who-can-see-what. The
alternative (a row per member per project, kept in sync by triggers) leaves two sources of
truth that drift. Cost of this choice: `get_unread_total` and the push Edge Function both
currently `INNER JOIN project_members` and must become LEFT JOIN with defaults, or org
members get zero unread counts and no push. That rewrite largely overlaps with BACKLOG D1.

**Shared database with RLS**, not schema-per-tenant or database-per-tenant. It is what
Supabase is built for and what comparable products use at this stage. The residual risk —
one bad policy leaks across tenants — is mitigated by the single chokepoint function,
default-deny on new tables, and isolation tests.

**Default-deny for new tables.** Enable RLS with no policy, then add explicitly. Never start
from `USING (true)` and narrow later; that is how the current state happened.

## Rejected

- **Per-resource ACLs** (per idea/bug/message) — complexity explosion, no value for small teams.
- **Schema-per-tenant / database-per-tenant** — stronger isolation, but painful migrations and
  real ops cost. Revisit only if a contract demands it.
- **Project as the tenant boundary** (no org layer) — simpler, but no shared member directory,
  no place to attach billing, and per-project invites for every teammate.
- **`project_members` as the security boundary** — retained only for private projects and
  notification prefs. Making it authoritative reintroduces the sync-drift problem above.

## Known nuances

**One global profile per user.** Someone in two organizations has one `full_name` and one
avatar in both. No cross-org leak (each org sees only its own members), but no per-org display
name either. Slack allows per-workspace names; Linear does not. Not worth the complexity here.

**`project_members` carries two meanings** — access grant (private projects) and notification
preferences (`badge_enabled`, `notif_messages`). Anyone reading that table will assume it is
one or the other. It is both.

**Storage paths must encode the project.** Current paths are `${userId}/${timestamp}.jpg`,
which contain no project, so no storage policy can scope by project. Target is
`${projectId}/${userId}/${uuid}.jpg` with
`can_access_project((storage.foldername(name))[1]::uuid)`. Avatars move to their own bucket —
their visibility is org-wide, not project-scoped, so they would fight the project policy.

## Related

- Current (pre-migration) state: `docs/database.md` § Row Level Security,
  `docs/architecture.md` § Security model
- Migration sequence: `BACKLOG.md` § B (Sigurnost)
- Schema source of truth: `supabase/schema.sql`
