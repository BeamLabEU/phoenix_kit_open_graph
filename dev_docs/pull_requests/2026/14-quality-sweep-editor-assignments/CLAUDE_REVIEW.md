# Claude Review — PR #14 "Quality sweep: editor no longer duplicates templates, honest public cards, safer assignments; dropdown Backspace fix"

**Merge commit:** 07bd532
**Author:** mdon (main)
**Files:** `lib/phoenix_kit_og.ex`, `templates.ex`, `assignments.ex`,
`variables.ex`, `activity_log.ex`, `render*.ex`, `scene_edit.ex`, the three
admin LiveViews, `priv/static/assets/phoenix_kit_og.js`, `mix.exs`,
`priv/gettext/*`, `test/**`, `AGENTS.md`

## Summary of the change

- `/new` creates the row on its connected mount and `push_navigate`s
  (replace) to `/:uuid/edit`; "Untitled N" retries on a name collision.
- Public cards are honest: a wired slot with no value renders `""`, a
  remote http(s) image is dropped (never a stand-in), `[[site_*]]` /
  `[[page_url]]` come from configured origin, not the request `Host`.
- Assignments: Edit saves the row it opened (scope locked), New refuses a
  taken scope (`Assignments.create/6`, `update/4`), image slots refuse
  remote URLs.
- `Templates.delete/2` logs one `assignment.deleted` row per cascaded
  assignment, inside the delete's transaction, published after commit.
- Render cache key hashes only the globals the scene references.
- `refine_og/4` rescues *and* catches exits, logging identifiers only; the
  group tier now resolves publishing's group slug to its uuid.
- Hook bundle cut to the keyboard hook (pointer gestures moved to
  OpenFresco); Backspace in a focused `<select>` no longer deletes the
  selection; every `phx-change` form also carries `phx-submit`.

## Verification

- `Groups.fetch_group/1` in `phoenix_kit_publishing` returns
  `{:ok, %{"uuid" => _, "slug" => _, ...}}`, the shape
  `group_uuid_for_slug/1` matches; the publishing post map carries
  `group:` as a slug (mapper), so the old `metadata.group_uuid` lookup
  could never have hit.
- The bundle no longer references `PhoenixKitOGCanvas`, `data-pk-og-*` or
  the `og-editor-js-warning` banner anywhere in `lib/` or `test/`; nothing
  dangles after the pointer-gesture removal.
- Dropping `module_key` from the cache payload changes every cache key, so
  all PNGs rendered before this release are orphaned (pruned by TTL). That
  also covers the unbumped `@render_version`: the remote-URL image change
  alters what is drawn for the same inputs, but no old file can be served.
- `Repo.insert(mode: :savepoint)` in `insert_in_transaction/3` is a valid
  Ecto/Postgres option; a failed audit row cannot abort the delete.

## Findings

### IMPROVEMENT - MEDIUM — `Templates.delete/2` raised on an already-deleted row

The new transaction locked the template row with `FOR UPDATE` but threw the
result away. When a second admin had deleted the template between the list
render and the click, `Repo.delete/1` raised `Ecto.StaleEntryError` and the
LiveView crashed instead of showing a flash (the handler's `{:error, _}`
branch was unreachable for this case).

**Fixed:** a nil lock result rolls back with `:not_found`; the failure goes
through `ActivityLog.log/4` (`failed: true`, `reason: "not_found"`) and the
list shows its existing "Could not delete template." flash. Test added in
`templates_test.exs`.

### NITPICK — test compile warning

`scene_edit_test.exs` matched on `alpha: 0.0`, which OTP 27 warns about
(matches only `+0.0`). **Fixed:** bind and compare with `==`.

### Not changed

- `untitled_number/0` calls `Templates.list/0`, which loads every canvas
  JSONB just to read names. It runs once per `/new` and the template count
  is small; a names-only query is the fix if a host ever has hundreds.
- `Variables.canonical_host_origin/1` hardcodes `https://`. The resolver
  returns a host, and a canonical host is https in practice.
- `EditorLive.mount/3` still writes on the connected `/new` mount; deliberate
  (see PR #13 review) and now guarded against reconnect duplication.
- An UNWIRED slot still prints `{{slot}}` on the public card — already
  tracked as a TODO in AGENTS.md.

## Gate

`mix precommit` clean; `mix test`: 289 tests, 0 failures, 3 excluded
