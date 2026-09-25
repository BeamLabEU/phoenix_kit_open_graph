# Claude Review — PR #13 "Actor and activity logging through core"

**Merge commit:** d51739d
**Author:** mdon (main)
**Files:** `lib/phoenix_kit_og/activity_log.ex`, the three admin LiveViews,
`lib/phoenix_kit_og.ex`, `mix.exs`, `mix.lock`,
`test/core_pin_conformance_test.exs`, `AGENTS.md`, `priv/gettext/*`

## Summary of the change

- The three per-LiveView `actor_opts/1` helpers are replaced by core's
  `PhoenixKitWeb.Actor.opts/1` (scope first, bare user as fallback).
- `ActivityLog.maybe_log/3` drops its own `Code.ensure_loaded?` /
  `Postgrex :undefined_table` / catch-all guards and calls
  `PhoenixKit.Activity.log/3`, which rescues and catches `:exit`/`:throw`
  itself.
- Core floor `~> 2.0` → `>= 2.38.0 and < 3.0.0`, with the conformance test
  and AGENTS.md updated to match; `js_sources/0` gains `@impl`.
- Admin header: `page_section` / `page_section_path` / `page_crumbs` /
  `page_title` trail in place of the `"OpenGraph — …"` titles; gettext
  catalogs regenerated.

## Verification

- Fetched `phoenix_kit` 2.38.0 from Hex: `PhoenixKitWeb.Actor` and
  `Activity.log/3` / `log_failed/3` all exist there, so the floor is right.
  Also checked against the locked 2.40.1.
- `Activity.log/3` treats a `nil` `:metadata` as `%{}` (`metadata_opt/1`) and
  nil optional fields as absent, so dropping the old `Map.reject` nil
  filter changes nothing.
- `Actor.opts/1` reads `:phoenix_kit_current_scope` first. The admin
  `live_session` and the test `on_mount` hook both set it, so attribution
  still works and is now consistent with other modules.
- Core's admin layout reads the `page_section*` / `page_crumbs` assigns off
  the socket (core's own `Settings` LV does the same).
- The old `"OpenGraph — …"` msgids are gone from `.pot` and every `.po`.
  Nothing still references them.

## Findings

### IMPROVEMENT - MEDIUM — `/new` still logs an anonymous `template.created`

`EditorLive.load_or_create_template/3` (`:new`) inserted the draft template
without opts. Its comment said the actor gets threaded in on the first save.
The PR switched every other call site to `Actor.opts(socket)` but missed this
one, so every template's creation row had no actor. The scope is already
on the socket at mount (the `on_mount` hook runs first).

**Fixed:** `Templates.create(attrs, Actor.opts(socket))`. The test router
gains the `/new` route. `EditorLiveTest` opens `/new` as a signed-in scope
and asserts that a `template.created` row names that user.

### IMPROVEMENT - MEDIUM — failed writes don't use core's `log_failed/3`

Core 2.38 ships `Activity.log_failed/3` for "a user action that did not
land". It stamps `"db_pending" => true` so core's feed can tell an attempt
from an action, and it skips the notification fan-out. The PR moved onto
core's API but still sent failure rows through plain `log/3`. Those rows
looked like real actions to core readers and were eligible for fan-out.

**Fixed:** both `{:error, _}` clauses of `ActivityLog.log/4` go through a
private `log_failed/3` that calls core's. The module's own `failed` /
`reason` metadata is kept (AGENTS.md and existing tests rely on it). New
`templates_test` case asserts the `db_pending` marker.

### NITPICK — "New template" untranslated

The editor's header title for `/new` is now `gettext("New template")`, but
the msgid had an empty `msgstr` in all 7 locales. That string used to be
only a button label. Now it heads the page.

**Fixed:** translated in de, es, et, fr, it, pl, ru.

### Not changed

- The edit page's crumb is `%{label: template.name}` with no path. That's
  deliberate: the templates list is the only page above it, and that's
  already the section link.
- `EditorLive.mount/3` and `TemplatesLive.mount/3` query the DB in mount.
  This is older than the PR, and `:new` already gates its insert on
  `connected?/1`. Moving it to `handle_params` is out of scope here.

## Gate

`mix precommit` clean (compile `--warnings-as-errors`, format,
`credo --strict`, dialyzer). `mix test`: 165 tests, 0 failures, 3 excluded
(`:requires_superuser`), integration suite included.
