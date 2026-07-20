# Claude review — PR #4 (quality sweep)

Reviewed against `elixir:phoenix-thinking` and `elixir:ecto-thinking`. Read the
full diff (`git show <merge> -m --first-parent`, ~1,500 lines across `lib/` +
~730 across `config/`/`test/`/docs), cross-checked the new
`unique_constraint/3` index names against core's real `V154` migration, and
diffed the extracted JS bundle byte-for-byte against the inline `<script>` it
replaced. Two bugs found and fixed below; one dead-code/no-op finding fixed;
one pre-existing (not-this-PR) directive flagged but not touched.

## BUG - MEDIUM: crashed/canceled preview render double-wraps the error tag, leaking it into the flash text

**Files**: `lib/phoenix_kit_og/web/assignments_live.ex:417-424`,
`lib/phoenix_kit_og/web/editor_live.ex:442-449` (pre-fix)

Both LiveViews' new `handle_async(:preview, {:exit, reason}, socket)` clause
pre-wrapped the crash reason before handing it to `preview_error_message/1`:

```elixir
# assignments_live.ex
def handle_async(:preview, {:exit, reason}, socket) do
  ...
  preview_error: preview_error_message({:render_failed, reason}),
  ...
end
...
defp preview_error_message(reason), do: Errors.message({:render_failed, reason})
```

`preview_error_message/1`'s catch-all clause *already* wraps its argument in
`{:render_failed, reason}` before handing it to `Errors.message/1` — this is
the same helper the sibling `{:ok, {:error, reason}}` clause calls with the
*raw* reason. Pre-wrapping produces a nested tuple, and `Errors.message({:render_failed, x})`
does `inspect(x)` — so the literal atom tag leaks into the user-facing flash:

```
iex> preview_error_message({:render_failed, :killed})
"Preview render failed: {:render_failed, :killed}"
```

`editor_live.ex` has the same bug with a different (also-wrong) tag,
`:render_crashed`, producing `"Preview render failed: {:render_crashed, :killed}"`.

This isn't a rare path — `cancel_async(socket, :preview)` (called on every
field edit, right before `start_async`, to supersede any in-flight render)
`Process.exit`s the running task, which is exactly what routes through this
`{:exit, reason}` clause. Any admin editing the modal fast enough to cancel an
in-flight render, or hitting a genuine rasterizer crash, sees the leaked
internal tag in their flash message.

**Fix applied**: pass the raw `reason` through in both `:exit` clauses,
matching the sibling `{:ok, {:error, reason}}` clause — `preview_error_message/1`
already does the single wrap.

**Not covered by an automated test** — reaching this path needs a live
`start_async`/`cancel_async` race or a rasterizer crash, and this repo has no
LiveView test harness yet (`AGENTS.md` TODOs call out a shared `LiveCase` +
`Test.Endpoint` as blocked/future work, same gap noted in PR #1's review).
Verified by extracting the exact clause bodies into a standalone `.exs` and
evaluating both the buggy and fixed call shapes (see the reasoning above) —
flagging here so it's on record rather than silently assumed-tested.

## IMPROVEMENT - MEDIUM: new `Variables.global_description/1` is dead code; `EditorLive.Template` kept its own diverging copy

**Files**: `lib/phoenix_kit_og/variables.ex:95-102`,
`lib/phoenix_kit_og/web/editor_live/template.ex` (pre-fix)

This PR added `Variables.global_label/1` *and* `Variables.global_description/1`
as the canonical, extractor-visible, translated copy for the OG-owned globals
(`site_host`, `site_url`, `site_name`, `page_url`, `page_locale`). `global_label/1`
is wired into `AssignmentsLive`'s wire-slot dropdown
(`PhoenixKitOG.Variables.global_label(v.name) || v.label`). `global_description/1`
was never called anywhere — `EditorLive.Template`'s `globals_info` banner kept
its own pre-existing private `global_description/5-clause-function`, which
this PR gettext-wrapped in place rather than replacing. The two functions
share a name and purpose but diverged in wording for every single key (e.g.
`site_url`: "Site's endpoint URL (from app config)" in the private copy vs.
"e.g. https://example.com" in the new canonical one) — exactly the "two lists
that must stay in sync" pattern, except one of the two lists was unreachable
from the start.

**Fix applied**: `globals_info/1` now calls `Variables.global_description(name) || name`
(mirroring the `global_label` pattern already used by `AssignmentsLive`); the
private duplicate in `EditorLive.Template` is deleted, and `Variables` is
added to that module's alias list. This changes the visible banner text for
the five globals from the deleted copy's full-sentence wording to the
canonical copy's `e.g. ...` example wording — the same information, one
source of truth, and it also means a future consumer-module-declared global
can reuse `global_description/1` instead of a third private copy.

## Not fixed (pre-existing directive, out of scope for this PR)

**File**: `lib/phoenix_kit_og/gettext.ex:18`

```elixir
# Generated Gettext.Backend callbacks trigger `call_without_opaque`
# warnings from Expo.PluralForms — a known false positive in gettext ≥ 0.26.
@dialyzer {:no_opaque, []}
```

Every other `@dialyzer` directive in this codebase (and in core) uses the
`{option, [function: arity, ...]}` form with an actual function list (e.g.
`{:nowarn_function, comments_enabled?: 0}` in core's `media_canvas_viewer.ex`).
An **empty** function list scopes the suppression to zero functions — per
Erlang's `-dialyzer()` attribute semantics this is a no-op; the module-wide
form is the bare atom `@dialyzer :no_opaque`, not a tuple with `[]`. As
written, the directive doesn't suppress anything the comment says it's meant
to suppress. Flagging rather than fixing: `mix dialyzer`'s pre-existing
warning count was reported unchanged by this PR's own author-run gate
(FOLLOW_UP.md: "9 pre-existing warnings unchanged"), so this directive isn't
currently masking a *new* regression — worth a follow-up to either supply the
real function list or switch to the bare-atom module-wide form.

## Gate

- `mix format --check-formatted` — clean.
- `mix compile --warnings-as-errors` — clean (including after this review's
  two fixes).
- `PHOENIX_KIT_PATH=../phoenix_kit mix test` — 87 tests, 0 failures, 17
  excluded (no PostgreSQL in this sandbox — the harness's own designed
  fallback, not a failure).
- `mix credo --strict` — 5 refactoring / 17 design suggestions, same standing
  baseline as before this review's fixes (confirmed by re-running after).
- `mix dialyzer` — 9 warnings, `Total errors: 9` (first-run PLT build for the
  full local-core dependency tree, so it took a while). All 9 are in code this
  PR didn't touch — 3 unreachable guard clauses (`phoenix_kit_og.ex:243`,
  `assignments.ex:147,159`), 3 unreachable pattern-match branches
  (`errors.ex:82` `truncate/1`, `svg.ex:463`, `assignments_live.ex:307`
  `do_save/2`'s catch-all `{:error, reason}` — dialyzer infers both calls in
  that `with` can only fail with `%Ecto.Changeset{}}`), and 2 `unknown_function`
  for `phoenix_kit_publishing`'s `Posts.list_posts/1` / `Groups.list_groups/1`
  (real at runtime, guarded via `Code.ensure_loaded?/1` +
  `function_exported?/2`, invisible to Dialyzer since that dependency isn't
  compiled into this repo). Matches the PR author's own reported baseline
  count exactly (9) — confirmed unchanged, not a regression from this PR or
  this review's fixes.
