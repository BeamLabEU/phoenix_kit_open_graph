# PR #13 follow-up

Triage of [CLAUDE_REVIEW.md](CLAUDE_REVIEW.md) against current `main`.

## Fixed (pre-existing)

- ~~IMPROVEMENT - MEDIUM — `/new` still logs an anonymous
  `template.created`~~ — `load_or_create_template/3` passes
  `Actor.opts(socket)` to `Templates.create/2`
  (`lib/phoenix_kit_og/web/editor_live.ex:460-463`); pinned by the `/new`
  case in `test/phoenix_kit_og/web/editor_live_test.exs`. No per-LiveView
  `actor_opts/1` helper remains in `lib/`.
- ~~IMPROVEMENT - MEDIUM — failed writes don't use core's `log_failed/3`~~ —
  both `{:error, _}` clauses of `ActivityLog.log/4` route through the private
  `log_failed/3`, which calls `PhoenixKit.Activity.log_failed/3`
  (`lib/phoenix_kit_og/activity_log.ex:50-71`, `:91-94`); pinned by the
  `db_pending` case in `test/phoenix_kit_og/templates_test.exs`.
- ~~NITPICK — "New template" untranslated~~ — the msgid has a non-empty
  `msgstr` in all seven locale files under `priv/gettext/`.

The review's two "Not changed" notes (the edit crumb has no path; `mount/3`
reads the DB) were recorded as deliberate and ask for no change.

## Open

None.
