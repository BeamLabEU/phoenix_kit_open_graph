# PR #14 follow-up

Triage of [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md) against current `main`.

## Fixed

- ~~IMPROVEMENT - MEDIUM — `Templates.delete/2` raised on an already-deleted
  row~~ — a nil `FOR UPDATE` result rolls back with `:not_found`
  (`lib/phoenix_kit_og/templates.ex`); pinned by the "already deleted" case in
  `test/phoenix_kit_og/templates_test.exs`.
- ~~NITPICK — test compile warning~~ — `scene_edit_test.exs` compares
  `alpha == 0`.

## Open

None. The "Not changed" notes were recorded as deliberate.

## GPT release verification — open follow-ups

Independent verification of 0.3.8 is recorded in [GPT_REVIEW.md](GPT_REVIEW.md).
The published package matches the release tag, and both repository checks pass.
The following findings remain open; no implementation changes were made in this
verification pass:

- **BUG - MEDIUM:** template deletion can log a cascaded deletion for an
  assignment that concurrently moved to another template and survived.
- **BUG - MEDIUM:** the new assignment-update path raises on a stale row;
  deletion between the LiveView's lookup and update can crash its save handler.
- **BUG - MEDIUM (pre-existing):** public fallbacks omit image fills on shapes,
  allowing their unresolved-image stand-ins onto public cards.
