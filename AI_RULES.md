# AI Development Rules

## General

- Reuse existing code whenever possible.
- Keep changes minimal.
- Preserve the existing architecture.
- Do not rewrite working code without a good reason.

---

## Vue / Quasar

- Use Composition API.
- Use <script setup>.
- Prefer composables over duplicated logic.
- Keep components focused.
- Do not create unnecessary wrapper components.

---

## Pinia

- Business logic belongs in Pinia stores.
- UI state belongs in components.
- Avoid duplicated state.
- Reuse existing stores.

---

## Supabase

- Never modify the database directly.
- All schema changes must be implemented as migrations.
- Prefer RLS over frontend authorization.
- Reuse existing queries whenever possible.
- After creating/editing a migration file, ALWAYS flag it as its own
  standalone paragraph — a whole separate block set off by blank lines
  before and after, not folded into a sentence inside a larger paragraph of
  other text. e.g.:

  ⚠️ Napravljena nova migracija, treba `supabase db push` prije testiranja.

  Never leave `supabase db push` as just a line inside a bash snippet, and
  never bury it mid-paragraph — both get skipped over. This has already
  caused silent bugs (`organizations_update` policies, `get_invitation_preview`)
  where the fix was written but never applied.

---

## Capacitor

- Keep platform-specific code isolated.
- Prefer official Capacitor plugins.
- Avoid custom native code unless necessary.

---

## Code Style

- Follow the existing naming conventions.
- Keep functions small.
- Avoid deep nesting.
- Prefer early returns.

---

## Before Coding

Always:

1. inspect existing implementation
2. search for similar code
3. reuse patterns already present
4. explain the implementation plan before large changes

---

## Never

- introduce new dependencies without approval
- duplicate business logic
- break existing APIs
- remove comments explaining business rules

---

## When Unsure

Stop and ask instead of guessing.
