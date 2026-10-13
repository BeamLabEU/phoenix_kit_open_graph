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
