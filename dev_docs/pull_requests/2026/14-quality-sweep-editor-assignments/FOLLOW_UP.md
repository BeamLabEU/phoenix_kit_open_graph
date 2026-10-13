# PR #14 follow-up

Triage of [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md) against current `main`.

## Fixed

- ~~IMPROVEMENT - MEDIUM — `Templates.delete/2` raised on an already-deleted
  row~~ — a nil `FOR UPDATE` result rolls back with `:not_found`
  (`lib/phoenix_kit_og/templates.ex`); pinned by the "already deleted" case in
  `test/phoenix_kit_og/templates_test.exs`.
- ~~NITPICK — test compile warning~~ — `scene_edit_test.exs` compares
  `alpha == 0`.

## Fixed after [GPT_REVIEW.md](GPT_REVIEW.md)

All three findings reproduced on reading the code and are fixed.

- ~~BUG - MEDIUM — cascade audit can report deletion of a surviving
  assignment~~ — `Templates.delete/2` now deletes the children itself with
  `Assignments.delete_for_template/1` (`DELETE … RETURNING`) inside the
  transaction and audits the rows returned; the parent `FOR UPDATE` lock stays
  to exclude new references. A row a concurrent transaction moved to another
  template is excluded when the delete re-checks its `WHERE` and is never
  logged. Pinned by the `delete_for_template/1` case in `assignments_test.exs`
  and the existing cascade cases in `templates_test.exs`. The two-connection
  interleaving itself is not in the suite (the SQL sandbox serialises it).
- ~~BUG - MEDIUM — assignment edit still has a stale-row crash window~~ —
  `Assignments.update/4` passes `stale_error_field: :uuid`, so a vanished row
  is an `{:error, changeset}` on `:uuid`; `AssignmentsLive.saved/2` answers it
  with the not-found flash and closes the modal. Pinned by the "removed since
  it was loaded" case in `assignments_test.exs`.
- ~~BUG - MEDIUM (pre-existing) — public image fallback misses image fills on
  shapes~~ — `Render.Media` inlines a shape's static image-fill media UUID and,
  in `:public` mode, drops a shape whose image fill is unresolved or remote
  (as it does an image element); `:preview` keeps the stand-in. Pinned by the
  "a shape's image fill" cases in `render/media_test.exs`.

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
