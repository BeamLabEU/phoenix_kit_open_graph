# GPT review — PR #14 and release 0.3.8

Reviewed 2026-10-13 against release commit `2bd9fa37be883745c45969cbd6d7f28d808dcdbc`.
PR merge: `07bd53264f3b4103adb3cb46efa23396edc80aeb`.

## Release verification

- Remote `main` and the peeled annotated tag `0.3.8` both point to the release commit.
- Hex 0.3.8 is published, has documentation, and is not retired. Its core
  requirement is `>= 2.38.0 and < 3.0.0`; `resvg` remains optional.
- Downloaded `https://repo.hex.pm/tarballs/phoenix_kit_og-0.3.8.tar` and compared
  every packaged file with the tag: **37 files, zero differences**. Archive
  SHA-256 matches Hex's release checksum:
  `9f1a3254a9fc9147ebf2222b7e4004aadfd4b0aa314021bb2d08feaa34680897`.
- Hex publication timestamp: `2026-10-13T11:27:09.899151Z`. GitHub release
  publication timestamp: `2026-10-13T11:27:17Z`; it is neither draft nor prerelease.
  These timestamps confirm Hex publication preceded GitHub release publication;
  they do not independently establish when the tag was pushed.

## Findings

### BUG - MEDIUM — cascade audit can report deletion of a surviving assignment

Location: `lib/phoenix_kit_og/templates.ex:71`.

The template's `FOR UPDATE` lock blocks new foreign-key references, but does not
freeze existing assignments. The plain `Assignments.list_for_template/1` query
captures rows that can subsequently be moved to another template or removed by
another transaction before the foreign-key cascade reaches them. Logging every
row from that earlier snapshot therefore does not identify exactly what was
deleted.

Reproduced with the actual `Templates.delete/2`, using separate database
connections against the test database:

1. Create templates A and B and an assignment referencing A.
2. Another transaction locks the assignment with `FOR UPDATE`.
3. Start `Templates.delete(A)`; wait until its `DELETE` is blocked on that row.
   It has already collected the assignment snapshot.
4. The other transaction changes the assignment to B and commits.
5. Template deletion completes successfully. The assignment remains attached
   to B, but an `assignment.deleted` activity entry says it cascaded with A.

Observed: `assignment_survived: true`, `cascade_deletion_audit_rows: 1`.
This contradicts the new audit guarantee and was not covered by the existing
tests. Suggested follow-up: delete the child rows with `DELETE ... RETURNING`
inside the template-delete transaction and audit the rows actually returned,
while retaining the parent lock to exclude new references.

### BUG - MEDIUM — assignment edit still has a stale-row crash window

Locations: `lib/phoenix_kit_og/assignments.ex:97` and
`lib/phoenix_kit_og/web/assignments_live.ex:357`.

The newly added `Assignments.update/4` uses `Repo.update/1` without stale-row
handling. The LiveView checks existence first, but another admin can remove the
assignment, or delete its template and cascade it away, between that check and
the update. Ecto then raises `Ecto.StaleEntryError`; `saved/2` only handles
returned tuples, so the exception escapes the event handler.

Reproduced the context failure by loading an assignment, deleting its row, then
calling `Assignments.update/4` with changed mapping content. It raises
`Ecto.StaleEntryError`. The database mutation was performed in the test database
and the probe's fixtures and activity rows were cleaned up.

Suggested follow-up: use Ecto's stale-error changeset handling or explicitly
return `{:error, :not_found}`, with a matching LiveView branch and regression
coverage. Claude's template-delete fix is valid, but does not cover this new
assignment-update path.

### BUG - MEDIUM — public image fallback misses image fills on shapes (pre-existing)

Location: `lib/phoenix_kit_og/render/media.ex:154`.

OpenFresco supports a shape with `fill: Scene.image_fill(...)`, and its slot
scanner recognizes that fill as image-typed. Media preparation resolves the
slot value but applies public fallbacks only to `type: :image` elements and the
canvas background. A shape with an unresolved or remote image fill survives;
OpenFresco emits the labeled stand-in on the public card. Static media UUIDs in
shape image fills also bypass `resolve_element/1`.

Reproduced with a shape named `photo-shape`, an image-fill `Hero` placeholder,
and `Hero = "https://cdn.example/x.png"`. After `Media.prepare(..., :public)`,
the shape remains; `OpenFresco.render_svg/2` emits a gray rectangle and a
`photo-shape` label. This gap existed in 0.3.7 and is not a new regression;
it limits the release's broad claim that public cards never show stand-ins.
It applies to stored/API-created scenes using shape image fills.

Suggested follow-up: prepare these fills and give unresolved public fills an
explicit fallback through the existing Media layer.

## Claims that held up

- Claude's missing-template lock check correctly returns `{:error, :not_found}`;
  its regression test passed.
- Publishing's actual `Groups.fetch_group/1` and mapper produce the
  `{:ok, %{"uuid" => ...}}` shape used by the group lookup.
- No removed `PhoenixKitOGCanvas`, `data-pk-og-*`, or `og-editor-js-warning`
  references remain in `lib/` or `test/`.
- Removing `module_key` from the serialized cache payload changes old keys,
  including when its former value was nil. The unchanged render-version
  constant does not leave old cache entries reachable for this release.

## Validation and scope

- `mix test`: **289 tests, 0 failures, 3 superuser-only tests excluded**.
- `mix precommit`: passed, including compile, dependency audit, formatting,
  strict Credo, Dialyzer with the repository's existing exclusions, and
  **6 JavaScript tests**.
- Additional temporary probes reproduced the findings above; they were not
  added to the shipped test suite. No fixture templates remain in the database.
- Reviewed the release and recorded follow-ups; no implementation changes or
  new release were made. The release-review skill's referenced Elixir thinking
  skills were unavailable after searching the installed skills and workspace.
