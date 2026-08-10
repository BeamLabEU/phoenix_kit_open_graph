# PR #5 — Let any module render an OG image, and add scene storage + editor

**Reviewed:** 2026-08-10 · **Author:** mdon · **Verdict:** merged, **with
substantial gate work applied on `main`.** Released in **0.3.0**.

+6148 / −6994 across 41 files. Reviewed as part of the phoenix_kit 2.0 sweep.

## The feature work

`PhoenixKitOG.og_image_url/5` becomes the generic entry point — previously the
only consumer was publishing, and that coupling lived in the call shape rather
than in anything essential. Scene storage, the OpenFresco editor and the
renderer sit behind it. The PR's own framing is accurate: nothing about OG image
generation was ever publishing-specific.

The PR depended on core #692, which shipped in core 2.0.0, so that is satisfied.

## `mix precommit` was already failing on `main` — this is the bulk of the work

The PR states this plainly and honestly: precommit exits non-zero, and did so at
the merge-base too (22 credo findings there, 22 here, delta zero). The author
declined to fold ~20 unrelated mechanical edits into a feature PR, which is a
defensible call for a PR — but precommit is this umbrella's release gate, and
this sweep cuts a release. So it had to be cleared here.

**22 credo findings → 0**, in three groups:

1. **12 "nested modules could be aliased"** — mechanical. Added the missing
   aliases (`Storage`, `Storage.Manager`, `Posts`, `Groups`, `Render.Media`,
   `Web.StagePlaceholder`, `Render.Cache`, `Test.Repo`) and switched the call
   sites. Zero behaviour change.
2. **6 "function body nested too deep"** — extracted the inner block in each
   case into a named private function: `cache_and_url/2` (render.ex),
   `put_resolved/3` and `fallback_background/2` (render/media.ex),
   `validate_flat_string_map/2` (schemas/assignment.ex), and
   `put_preview_value/3` (web/assignments_live.ex).
3. **4 "function is too complex"** — all in `scene_edit.ex`, all the same shape:
   a wide dispatch over a field/kind string.
   - `update_element/4` (complexity 18) → a `field_kind/1` classifier plus one
     small function per field family.
   - `update_canvas/3` (11) → `put_canvas_field/3` function clauses.
   - `set_anchor/4` (15) → `put_anchor/5` + `put_existing_anchor/5` clauses.
   - `insert/2` (10) → `build_element/5` clauses, one per Insert-menu kind.

   These are behaviour-preserving re-shapes of dispatch tables, verified by
   `scene_edit_test.exs` (16 tests) after each step.

**Then dialyzer ran for the first time.** `quality.ci` is format → credo →
dialyzer, so with credo failing, dialyzer had never executed on this module.
Clearing credo surfaced six findings, none of which is a defect:

- **Two are environment artifacts.** `OpenFresco.render/3` is specced
  `{:ok, binary(), map()} | {:error, term()}`, but the PNG rasterizer is an
  optional backend the *host* installs. None is present in this package's own
  dev environment, so dialyzer proves the success branch — and the function
  handling it — unreachable here. Both disappear wherever OG rendering can
  actually run.
- **Four are defensive clauses** dialyzer can prove dead from today's callers:
  the `{_scope, nil}` skip in the hierarchy walk, `truncate/1`'s short-string
  branch, and the generic `{:error, reason}` arm behind a changeset-only `with`.
  Deleting them would trade graceful degradation for a `FunctionClauseError` the
  moment a new caller appears.

Added `.dialyzer_ignore.exs` (the convention `phoenix_kit_billing`,
`phoenix_kit_emails` and `phoenix_kit_crm` already follow) with each entry
justified individually, and wired it via `ignore_warnings:`.

**One genuine conflict between the two tools.** `list_publishing_posts/1` and
`list_publishing_groups/0` call into `phoenix_kit_publishing`, an *optional*
peer that is not a dependency here. The calls are correctly guarded at runtime
(`Code.ensure_loaded?` + `function_exported?` + `rescue`), but dialyzer sees a
static call to a module not in the PLT and reports `unknown_function`. Switching
to `apply/3` fixes that and immediately trips credo's
`Refactor.Apply` ("avoid apply when the arity is known"). The two checks want
opposite code, so `apply/3` stays with a `# credo:disable-for-next-line` at each
call and a comment explaining why — a targeted disable, not a module-wide one.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0 — was failing on `main` before this |
| `mix test` | **89 tests, 0 failures** (17 excluded — no Postgres available) |
| `mix test test/phoenix_kit_og/scene_edit_test.exs` | **16 tests, 0 failures**, re-run after each refactor step |

## Caveat worth stating

The refactors in group 3 are the riskiest thing in this release. They are
behaviour-preserving by construction — each is a dispatch table turned into
clauses over the same keys — and `scene_edit_test.exs` passes throughout, but
16 tests is not exhaustive coverage of a property panel with this many fields.
The editor is worth a manual pass before relying on it.
