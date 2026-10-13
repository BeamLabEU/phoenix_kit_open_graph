# Follow-up

Findings from `CLAUDE_REVIEW.md`, re-verified against current code.

## Fixed (Batch 1 — 2026-10-13)

- ~~The migrations moduledoc carried a process narrative instead of saying
  what the migration guarantees~~ — rewritten to state what V1 guarantees
  (`lib/phoenix_kit_og/migrations.ex`).
- ~~Deleting a template silently removed its assignments through the foreign
  key~~ — the cascade stays (see Skipped), but the delete confirmation now
  states how many assignments go with the template and each one leaves its
  own `assignment.deleted` activity row
  (`lib/phoenix_kit_og/templates.ex`, `lib/phoenix_kit_og/web/templates_live.ex`).

## Skipped (with rationale)

- **Changing the assignments foreign key away from `ON DELETE CASCADE`** — a
  shipped migration step is immutable, and the reviewer filed it as a
  nitpick. The behaviour it worried about is covered by the confirmation and
  audit rows above.

## Files touched

| File | Change |
|---|---|
| `lib/phoenix_kit_og/migrations.ex` | Moduledoc only |
| `lib/phoenix_kit_og/templates.ex` | Audit rows for cascaded assignments |
| `lib/phoenix_kit_og/web/templates_live.ex` | Confirmation states the count |

## Verification

`mix test` 291 tests, 0 failures. `mix precommit` clean.

## Open

None.
