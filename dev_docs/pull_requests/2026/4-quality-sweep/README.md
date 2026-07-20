# PR #4: Quality sweep — security hardening, JS-hooks bundle, async render, i18n, DB test harness

**Author**: @mdon
**Reviewer**: @claude
**Status**: Merged
**Commit**: `fcf3e5a` (merge; branch tip `b662942`)
**Date**: 2026-07-20

## Goal

First full quality sweep of `phoenix_kit_og` since the initial module PR (#1),
plus a reconciliation of a stale, unmerged docs branch (PR #3, superseded by
this PR). Security hardening (SVG injection, `file://` local-read, canvas-size
DoS, concurrent-assignment races), moves the editor's JS hooks from an inline
`<script>` (broken on LiveView navigation) to a `js_sources/0` bundle, moves
preview rendering off the LiveView process via `start_async`/`cancel_async`,
adds an own `PhoenixKitOG.Gettext` backend + translations across 7 locales,
adds a from-scratch DB test harness + context tests, and renumbers every
`V139`/`V152` migration reference to the shipped `V154`.

## What Was Changed

### Files Modified

| File | Change |
|------|--------|
| `lib/phoenix_kit_og.ex` | `js_sources/0`; `refine_og/4` docstring corrected to match shipped swap-and-size-hints behavior |
| `lib/phoenix_kit_og/activity_log.ex` | Logs a `failed: true` audit row on `{:error, _}`, threading `changeset.data` so a failed update/delete keeps its `resource_uuid` |
| `lib/phoenix_kit_og/errors.ex`, `lib/phoenix_kit_og/gettext.ex` (new) | Own `PhoenixKitOG.Gettext` backend instead of borrowing core's `PhoenixKitWeb.Gettext` |
| `lib/phoenix_kit_og/render.ex`, `render/svg.ex` | SVG-attribute escaping on all interpolated geometry, glow-filter id sanitized to a safe charset, `file://` hrefs dropped, canvas width/height clamped (`@max_dim 4000`) on both the SVG viewBox and rasterizer output buffer |
| `lib/phoenix_kit_og/render/cache.ex` | TTL + count-cap eviction (`prune/0`, called probabilistically from `write/2`) |
| `lib/phoenix_kit_og/schemas/assignment.ex` | `unique_constraint/3` on the two V154 partial indexes — a concurrent double-insert now returns `{:error, changeset}` instead of raising `Ecto.ConstraintError` |
| `lib/phoenix_kit_og/variables.ex` | `global_label/1` + `global_description/1` — literal `gettext/1` clauses (extractor-visible) for the OG-owned globals |
| `lib/phoenix_kit_og/web/assignments_live.ex`, `editor_live.ex` | Preview render moved off the LV process (`start_async`/`cancel_async` + `handle_async`), `handle_info` catch-all, i18n wrapping |
| `lib/phoenix_kit_og/web/editor_live/template.ex` | Inline JS hook `<script>` removed (now shipped via `js_sources/0`); i18n wrapping |
| `priv/static/assets/phoenix_kit_og.js` (new) | The editor's drag/resize + keyboard hooks, moved out of the inline `<script>`, registered on `window.PhoenixKitOGHooks` |
| `lib/phoenix_kit_og/web/image_controller.ex` | `X-Content-Type-Options: nosniff` on served PNGs |
| `test/support/{test_repo,data_case}.ex`, `config/{config,test}.exs`, `test/test_helper.exs` (new) | DB test harness — sandbox, migration bootstrap via `PhoenixKit.Migration.ensure_current/2`, `:integration` auto-exclude when Postgres or the OG tables (core V154) are unavailable |
| `test/phoenix_kit_og/{assignments,templates}_test.exs` (new) | Context tests: upsert/clear, the constraint-race guard, the most-specific-wins resolution hierarchy, Templates CRUD + activity (incl. the failed-update-keeps-uuid case) |
| `priv/gettext/**` (new) | `PhoenixKitOG.Gettext` backend + translations (7 locales) for the common UI string set |
| `AGENTS.md`, `CHANGELOG.md`, `dev_docs/pull_requests/2026/1-initial-og-module/FOLLOW_UP.md` (new) | V152→V154 renumbering, Testing + Activity-logging sections, triage of the PR #1 review |

## Implementation Details

- **`cancel_async` is load-bearing, not decorative**: `start_async` with a
  repeated key discards a *superseded result* but does not kill the
  in-flight task — without an explicit `cancel_async/2` first, a rapid
  sequence of field edits would leave every earlier rasterize still burning
  CPU in the background. Both LiveViews call `cancel_async(socket, :preview)`
  immediately before `start_async(:preview, ...)`.
- **SVG hardening** is defense-in-depth against the canvas being a
  free-form JSONB map (`is_map` is the only schema-level check) — a crafted
  `width`/`height` could otherwise inject markup (non-numeric string) or
  make the rasterizer allocate an unbounded pixel buffer (numeric DoS).
- **Migration ownership**: this repo owns no migrations — `phoenix_kit_og_templates`/`_assignments`
  ship in core's `V154` (verified against `phoenix_kit/lib/phoenix_kit/migrations/postgres/v154.ex`,
  including the two partial-unique-index names the new `unique_constraint/3`
  calls reference — confirmed they match).

## Testing

- [x] Unit tests added/updated — Templates/Assignments context tests, Cache
      eviction tests, Svg injection/DoS-hardening tests.
- [ ] Integration tests pass — **not independently verified**: this sandbox
      has no PostgreSQL, so the 17 DB-backed (`:integration`-tagged) tests are
      excluded by the harness's own designed fallback, same as a fresh
      standalone install without core V154. Confirmed via code reading that
      the two referenced unique-index names in `Assignment.changeset/2` match
      the real V154 migration.
- [x] Backward compatibility verified — `mix compile --warnings-as-errors`,
      `mix format --check-formatted` clean; `mix credo --strict` unchanged
      from the pre-existing baseline (5 refactoring / 17 design suggestions).
- [x] Documentation updated (AGENTS.md, CHANGELOG.md already covered by the PR).

## Related

- Previous: [#1](/dev_docs/pull_requests/2026/1-initial-og-module/)
- Review: [CLAUDE_REVIEW.md](./CLAUDE_REVIEW.md)
