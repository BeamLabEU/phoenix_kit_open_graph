# Follow-up

Findings from `CLAUDE_REVIEW.md`, re-verified against current code.

## Fixed (pre-existing)

- ~~Async render left running after the editor closed~~ — `cancel_async` and
  `handle_async` cover it (`lib/phoenix_kit_og/web/editor_live.ex`).

## Fixed (Batch 1 — 2026-10-13)

- ~~`@dialyzer {:no_opaque, []}` in `gettext.ex` silenced nothing~~ — replaced
  by a skip scoped to the generated `<locale>_default_plural/1`, which the
  module's first `ngettext` call makes a real warning
  (`lib/phoenix_kit_og/gettext.ex`).
- ~~`Variables.global_description/1` had no caller, leaving five orphan
  msgids~~ — wired into the editor's Insert menu, so each global shows its
  description (`lib/phoenix_kit_og/variables.ex`,
  `lib/phoenix_kit_og/web/editor_live/template.ex`).

## Files touched

| File | Change |
|---|---|
| `lib/phoenix_kit_og/gettext.ex` | Scoped dialyzer skip |
| `lib/phoenix_kit_og/web/editor_live/template.ex` | Insert menu shows global descriptions |

## Verification

`mix test` 291 tests, 0 failures. `mix precommit` clean (dialyzer 5 skipped,
0 unnecessary).

## Open

None.
