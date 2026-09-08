# AGENTS.md

Guidance for AI agents working on `phoenix_kit_og` (repo directory
`phoenix_kit_open_graph`, module `PhoenixKitOG`).

## Overview

OpenGraph template + hierarchical assignment plugin for PhoenixKit, built on
`open_fresco` (scene model, server-authoritative editor stage, server-side
SVG/PNG renderer). It ships three things:

- **Templates** — a WYSIWYG editor for OG image designs. The stage is
  `OpenFresco.Editor` (server-authoritative SVG with drag/resize); this module
  owns the chrome: insert menu, property panel (text / image / rect / button /
  stamp elements, gradients, anchors), slots panel, always-on preview pane.
  `{{slot}}` and `[[global]]` variable syntax throughout.
- **Assignments** — bind a template to a scope inside a consumer module's
  hierarchy (`post → group → default`). Admin modal for CRUD + live preview
  against a real published post.
- **Renderer** — `OpenFresco.render/3` behind `PhoenixKitOG.Render`; PNGs are
  cached on disk and served from `/og-image/:key`. Consumers integrate through
  `refine_og/4` (publishing-shaped) or `og_image_url/5` (any module).

What stays this module's: slot wiring + assignment hierarchy, media-UUID →
`data:` URL resolution (`Render.Media`), `:public` vs `:preview` render modes,
PNG caching + the `/og-image/:key` route, activity logging, i18n. Layout, text
measurement, anchors, gradients and rasterizing are `open_fresco`'s.

- **Depends on:** `phoenix_kit` `~> 2.0` (Hex); `open_fresco` `~> 0.2`;
  `unicode_string` `~> 1.0` (UAX #14 line breaking for CJK/Thai — this module
  is multilingual, estimates are not enough); `resvg` `~> 0.5` **optional**
  (hosts opt in with `{:resvg, "~> 0.5"}`; never make it required, its
  `rustler_precompiled ~> 0.8.1` pin conflicts with hosts that need a newer
  one, and the rasterizer chain falls back to the `resvg` CLI, `rsvg-convert`
  or ImageMagick).
- **Consumed by:** `phoenix_kit_publishing` (`refine_og/4`,
  `preview_og_image_url/3`; it implements `og_variables/0` + `og_resolve/2`)
  and `phoenix_kit_projects` (`og_image_url/5` for public portal boards). Both
  treat this module as optional and guard every call with
  `Code.ensure_loaded?/1` + `function_exported?/3`.
- **Admin surface:** tab `OpenGraph` (`/admin/open-graph`, permission
  `phoenix_kit_og`, group `:admin_modules`) with subtabs Templates
  (`/admin/open-graph`) and Assignments (`/admin/open-graph/assignments`);
  editor at `/admin/open-graph/new` and `/admin/open-graph/:uuid/edit`. One
  public route: `GET <url_prefix>/og-image/:key`.
- **Module key** `"phoenix_kit_og"`; settings prefix `phoenix_kit_og_`.

## What this module does NOT do

- **No standalone Phoenix app** — a library. Endpoint and router come from the
  host; route helpers live in `PhoenixKitOG.Paths` and `PhoenixKitOG.Routes`.
- **No consumer-specific business logic** — the plugin knows nothing about
  posts, groups, or any consumer's data. Every variable a template renders
  comes through the consumer's `og_resolve/2`.
- **No image storage of its own** — media UUIDs resolve through
  `PhoenixKit.Modules.Storage` (core). Rendered PNGs live in
  `System.tmp_dir!()/phoenix_kit_og_cache/`, not `priv/static/` (see
  Landmines).
- **No layout, SVG or rasterizing of its own** — all `open_fresco`. Feature
  gaps go to `dev_docs/open_fresco_feedback_todo.md`, not into this repo.
- **No network fetches at render time** — OpenFresco reads nothing remote;
  every image reaching it is a `data:` URL. `file://` is rejected outright
  (a local-file-read primitive with no legitimate use).
- **No auth on `/og-image/:key`** — deliberate: crawlers carry no session.
  Consumers therefore only generate OG images for public resources
  (projects does so for public boards only, never capability portals).
- **No migrations of its own** — both tables ship in core's chain.

## Commands

```bash
mix deps.get
createdb phoenix_kit_og_test          # once; DB-backed tests are tagged :integration and auto-skip without it
mix test
mix precommit                # compile --warnings-as-errors + format + credo --strict + dialyzer; run before every commit
```

`phoenix_kit*` deps resolve from Hex. To run against a local checkout, export
`<APP>_PATH` (the dep's app name upper-cased plus `_PATH`); `pk_dep/3` in
`mix.exs` swaps the Hex pin for a `path:` dep at resolve time. Unset means the
Hex pin, so `mix hex.publish` is unaffected. Run `mix deps.get` with the var
exported before the first `mix test` (a stale lock aborts on the optional
`igniter` dep), and never commit a hand-edited `path:` tuple.

```bash
PHOENIX_KIT_PATH=../phoenix_kit mix deps.get && PHOENIX_KIT_PATH=../phoenix_kit mix test
```

Repo-local aliases:

- `mix quality` — `format` + `credo --strict` + `dialyzer` (applies formatting).
- `mix quality.ci` — `format --check-formatted` + `credo --strict` + `dialyzer`: it CHECKS formatting rather than applying it, so run `mix format` first.

## Conventions

- Module key `phoenix_kit_og`; tab ids `:admin_phoenix_kit_og`,
  `:admin_phoenix_kit_og_templates`, `:admin_phoenix_kit_og_assignments`; URL
  segment `open-graph` (hyphens). An assignment's `module_key` is the
  consumer's own `module_key/0` (e.g. `"publishing"`), never this module's.
- Paths: `PhoenixKitOG.Paths` (`templates/0`, `assignments/0`,
  `new_template/0`, `edit_template/1`) over `PhoenixKit.Utils.Routes.path/1`;
  never hardcode. Exception: `Render.cache_url/1` builds `/og-image/<key>` by
  hand from `PhoenixKit.Config.get_url_prefix/0`, because `Routes.path/1`
  injects the active locale and crawlers do not negotiate locales. The URL
  carries no `.png` suffix (a Phoenix route cannot follow `:key` with a
  literal suffix); crawlers sniff the content-type header.
- Routing: the two index pages ride `live_view:` on their tabs.
  `route_module/0` → `PhoenixKitOG.Routes` registers only the editor routes
  (`/admin/open-graph/new`, `/admin/open-graph/:uuid/edit`) in both
  `admin_routes/0` and `admin_locale_routes/0`, and `generate/1` mounts the
  public `/og-image/:key` route on the `:browser` + `:phoenix_kit_auto_setup`
  pipelines. Never put a path on a tab AND in the route module (duplicate-route
  error). Never hand-register plugin routes in a host router.
- LiveView macro: `use PhoenixKitWeb, :live_view` followed by
  `use Gettext, backend: PhoenixKitOG.Gettext`; function components use
  `use PhoenixKitWeb, :html`. The media picker comes from
  `use PhoenixKitWeb.Components.MediaBrowser.Embed`. No `LayoutWrapper` —
  the admin LVs render inside core's admin `live_session`. The editor's
  preview-platform switcher is core's `<.nav_tabs>` (event tabs dispatch
  `phx-value-tab`, so handlers match `%{"tab" => _}`).
- gettext: own backend `PhoenixKitOG.Gettext`, catalogs in `priv/gettext`
  (de, es, et, fr, it, pl, ru); `mix gettext.extract` +
  `mix gettext.merge priv/gettext`. Catalog data (the `[[global]]` labels and
  descriptions in `Variables`) is anchored with one literal `gettext/1` clause
  per name (`global_label/1`, `global_description/1`) — `gettext(v.label)`
  over an attribute is invisible to the extractor. Error copy goes through
  `PhoenixKitOG.Errors.message/1` at the UI boundary; contexts return atoms
  (`:not_found`, `:rasterizer_missing`, `:template_missing`, `:group_missing`,
  `{:render_failed, reason}`).
- JS hooks: two prebuilt bundles declared by `js_sources/0`, folded into the
  host's single LiveSocket by core's `:phoenix_kit_js_sources` compiler:
  this repo's `priv/static/assets/phoenix_kit_og.js` → `window.PhoenixKitOGHooks`
  (`PhoenixKitOGEditor`: nudge / delete / Ctrl+S at the LV level) and
  `open_fresco`'s `priv/static/open_fresco.js` → `window.OpenFrescoHooks`
  (`OpenFrescoEditor`: reports pointer gestures as canvas-space deltas; the
  LiveComponent applies them via `OpenFresco.Editor.Ops`). Never register a
  hook from an inline `<script>` — morphdom does not execute inserted script
  tags, so the hook vanishes on LiveView navigation.
- CSS: `css_sources/0` returns `[:phoenix_kit_og]` so the host's Tailwind
  scans this module's templates; nothing to add on the host side.
- `enabled?/0` reads `phoenix_kit_og_enabled` (default `false`), rescues and
  catches `:exit`, returns `false`.
- Never raise from the public API: `refine_og/4`, `og_image_url/5` and
  `preview_og_image_url/3` rescue everything and return the input map /
  `:none`. An OG image is decoration and must never take down the page it
  decorates.
- Activity logging: `PhoenixKitOG.ActivityLog` wraps `PhoenixKit.Activity.log/1`
  with `module: "phoenix_kit_og"`. `log/4` is a pipe step: it logs the success
  row on `{:ok, struct}` AND a failure row on `{:error, _}` (metadata
  `failed: true` + a coarse reason; for an update/delete the changeset's
  `data` still names the targeted record), so an invalid write leaves a trail.
  `maybe_log/3` is the direct form. Actor threads through `opts[:actor_uuid]`
  (`:mode` defaults to `"manual"`). Guards: `Code.ensure_loaded?`, silent on
  `Postgrex :undefined_table` (fresh host), warning-and-swallow on anything
  else. Actions: `template.{created,updated,deleted}`,
  `assignment.{created,updated,deleted,slot_mapping_updated}`. Metadata is
  PII-safe: names, counts, UUIDs only — never canvas blobs, image bytes, or
  `slot_mapping` content (users type into it).
- Soft delete: none. Deleting a template cascades its assignments (FK).
- Every OG card is 1200×630; the editor snaps a stray-sized scene back on
  mount. Renders clamp at 4000px per side (`@max_dimension`).
- The core pin stays a two-segment `~> 2.0` (`test/core_pin_conformance_test.exs`
  enforces it): a three-segment pin excludes later core minors and breaks
  `mix deps.get` for every host, and nothing in this repo would notice.
- Every table-backed schema uses `PhoenixKit.SchemaPrefix` and UUIDv7 PKs
  (`test/schema_prefix_conformance_test.exs` enforces the prefix).

### Landmines

- Hooks registered from an inline `<script>` work on a hard load, then vanish
  when navigating Templates list → editor (both in `live_session
  :phoenix_kit_admin`) → declare them via `js_sources/0`.
- A PNG cache under `priv/static/` trips the dev live-reload plug on every
  render and wipes modal state (and `priv/static` is read-only in a release)
  → keep the cache under `System.tmp_dir!()/phoenix_kit_og_cache/`.
- `StagePlaceholder.data_url/0` (a nested-SVG `data:` URL) is browser-only:
  rasterizers vary on nested `<image>` and draw a black square → it feeds the
  editor stage's sample mode only; preview and public renders keep
  OpenFresco's labeled stand-in.
- `image/png` with the default `; charset=utf-8` suffix makes Telegram drop
  the preview → `put_resp_content_type("image/png", nil)` in `ImageController`.
- A concurrent duplicate assignment insert raises `Ecto.ConstraintError` in
  the LV unless the changeset declares both partial unique indexes
  (`idx_og_assignments_unique_scoped`, `idx_og_assignments_unique_default`)
  via `unique_constraint/3` → keep those names in sync with core's migration.

## Architecture

```
lib/phoenix_kit_og.ex              PhoenixKit.Module impl; refine_og/4, og_image_url/5,
                                   preview_og_image_url/3; delegators to Templates/Assignments
lib/phoenix_kit_og/
  templates.ex                     Templates context (CRUD + activity)
  assignments.ex                   Assignments context (upsert, clear, slot mapping, hierarchy walk)
  variables.ex                     [[global]] registry, consumer-callback discovery, slot resolution
  scene_store.ex                   canvas JSONB <-> OpenFresco.Scene, lazy legacy migration, slots/1
  scene_edit.ex                    property-panel mutations on a scene
  errors.ex                        error atom -> translated flash copy
  activity_log.ex                  PhoenixKit.Activity wrapper
  paths.ex / routes.ex             path helpers / route_module
  gettext.ex                       PhoenixKitOG.Gettext backend
  render.ex                        render_url/2 facade, cache_url/1
  render/cache.ex                  on-disk PNG cache (key, atomic write, amortized prune)
  render/media.ex                  media UUID -> data: URL, :public fallbacks
  schemas/template.ex              phoenix_kit_og_templates
  schemas/assignment.ex            phoenix_kit_og_assignments
  web/templates_live.ex            /admin/open-graph
  web/assignments_live.ex          /admin/open-graph/assignments
  web/editor_live.ex (+ editor_live/template.ex)   /admin/open-graph/new, /:uuid/edit
  web/image_controller.ex          GET /og-image/:key
  web/stage_placeholder.ex         browser-only arrows stand-in for the stage's sample mode
priv/static/assets/phoenix_kit_og.js   PhoenixKitOGHooks bundle
priv/gettext/                      default.pot + 7 locales
dev_docs/                          fresco checklist / requirements / feedback; pull_requests/
```

### Two variable syntaxes

- `{{slot}}` — a template-local slot the assignment wires to a consumer
  variable. Slots appear in the assignments admin as fields to bind. Wiring:
  `%{"post_title" => "post_title"}`.
- `[[global]]` — resolved automatically from this module's globals
  (`site_url`, `site_host`, `site_name`, `page_url`, `page_locale`). Never
  wired; never shown in the slots panel.

`SceneStore.slots/1` (→ `OpenFresco.Substitute.slots/1`) lists the `{{...}}`
slots a scene uses as `[%{name, type: :text | :image}]`. OpenFresco takes slot
values and global values as two separate maps. `Variables.resolve/3` walks the
slot mapping: a `custom:` prefix is a literal typed by the author (or a picked
media UUID) and passes through verbatim; then globals; then the consumer's
`og_resolve/2`. A missing wire or unknown variable leaves the slot unresolved
(the renderer keeps `{{slot}}` visible). `Variables.global_values/1` prefers
`conn` fields and falls back to the `:endpoint` so the editor can preview real
values without a request.

### Hierarchy resolution

`Assignments.resolve_template_with_mapping/2` walks an ordered list of
`{scope_type, scope_uuid}` tuples, most specific first; the first assignment
wins and returns `{:ok, template, slot_mapping}` or `:none`. A `nil`
`scope_uuid` on any non-`"default"` scope is skipped ("no id at this tier",
e.g. a post without a group). `{"default", nil}` always trails and matches the
module-wide assignment whose `scope_uuid IS NULL`. Publishing's hierarchy:

```elixir
[{"post", post.uuid}, {"group", post.metadata.group_uuid}, {"default", nil}]
```

### Consumer contract

A module opts in by implementing two optional callbacks on its
`PhoenixKit.Module` implementation; discovery goes through
`PhoenixKit.ModuleDiscovery` matching on `module_key/0`.

| Callback | Shape | Notes |
|---|---|---|
| `og_variables/0` | `[%{name: String.t(), type: :text \| :image, label: String.t(), description: String.t()}]` | Declares the variables a template slot can bind to. The assignments UI filters by type, so an `:image` slot lists only image-typed vars. Merged with the globals in the "wire slots" dropdown. |
| `og_resolve/2` | `(var_name :: String.t(), context) -> value \| nil` | Fetches the value at render time. `context = %{module_key, resource, conn, language, page_url}` (`conn` may be `nil`). `nil` means unresolved. Exceptions are swallowed (treated as `nil`). An `:image` value may be a storage media UUID, a `data:` URL, or http(s). |

What the consumer calls back:

| Call | Returns | Use |
|---|---|---|
| `refine_og(og, conn, post, language)` | the `og` map, possibly with `:image`, `:image_width`, `:image_height`, `:image_type` replaced/added | Publishing, per public page render. Pass-through when disabled, when no template resolves, on render error, or on any raised exception. The returned map keeps every key the consumer passed in. |
| `og_image_url(module_key, hierarchy, resource, conn, opts)` | `{:ok, absolute_url} \| :none` | Any module; supplies its own hierarchy, most specific first, `{"default", nil}` trailing. `opts[:language]`. |
| `preview_og_image_url(post, conn, language)` | `{:ok, url} \| :none` | Publishing's editor: "what the plugin will produce" preview beside the manual override. |

When enabled, a consumer's per-resource OG override fields do not bypass the
plugin; they feed it (publishing's `og_resolve/2` reads them first).
`image_width`/`image_height` come from the scene canvas so the consumer's meta
component can emit `og:image:*` size hints (Telegram/Facebook pre-size the
card with them).

### Rendering

`Render.render_url/2` takes a template and
`%{values:, globals:, mode: :public | :preview, module_key:}` and returns
`{:ok, path}` (`/og-image/<key>`, absolutized by the caller) or
`{:error, term}`. Pipeline: `SceneStore.load` (lazy legacy-canvas migration)
→ `Render.Media.prepare` (media UUIDs → `data:` URLs; `:public` fallbacks) →
cache lookup → `OpenFresco.render/3` → atomic cache write.

- **Media** — `Render.Media` resolves storage UUIDs to local file bytes
  inlined as `data:image/*;base64,…`; `data:` and http(s) pass through (the
  renderer skips remote); `file://` and host-relative paths drop to `nil`.
- **Modes** — `:public` (crawler-facing): an unresolved image element is
  dropped and an unresolved image background falls back to the house dark
  solid (`#0b1220`) — never a stand-in in production. `:preview` (editor +
  assignments): unresolved image slots draw OpenFresco's labeled stand-in.
- **Rasterizer** — `:resvg` NIF preferred, then the `resvg` CLI,
  `rsvg-convert`, ImageMagick. `{:error, :rasterizer_missing}` when none is
  reachable; the seam then keeps the consumer's own image.
- **Fonts** — hosts configure `config :open_fresco, font_dirs: [...],
  font_files: [...]` (resvg fontdb, cached, not rescanned per render). Nothing
  to wire og-side; system fonts + DejaVu Sans / Liberation Sans / Arial are the
  default chain.
- **Cache** — `System.tmp_dir!()/phoenix_kit_og_cache/<16-hex>.png`. The key
  hashes `@render_version` (bump it when this side changes what it draws for
  the same inputs) + OpenFresco's engine version + template uuid +
  `updated_at` + the prepared scene + values + globals + module_key, so an
  upgrade on either side stops serving stale PNGs and a template edit orphans
  every old file. Writes are tempfile + rename (a concurrent read never sees a
  partial file). `write/2` prunes on ~2% of writes: files older than the TTL,
  then the oldest beyond the cap; tune with
  `config :phoenix_kit_og, cache_ttl_seconds: _, cache_max_files: _`
  (defaults 30 days / 5000). The cache is a performance layer, never a source
  of truth.
- **Serving** — `Web.ImageController.show/2`: key must be ≤ 64 lowercase hex
  chars (400 otherwise), 404 on a miss, `image/png` without charset,
  `cache-control: public, max-age=30d, immutable`, `x-content-type-options:
  nosniff`.

### Editor

`EditorLive` owns the scene document (load/save via `SceneStore`), the
property panel (`SceneEdit`), insert menu, keyboard nudges, media picker,
autosave (800 ms debounce; Ctrl+S / Save flush immediately; a header pill
shows saved / saving / unsaved) and the preview pane. `OpenFresco.Editor`
(LiveComponent) owns the stage and notifies with
`{:open_fresco_editor, stage_id, {:scene_changed, scene} | {:selected, id} |
{:selected_ids, ids}}`. Multi-select: the property panel follows the last
selected element; Delete and arrow-nudge apply to the whole set
(`Ops.delete_many/2`, `Ops.move_many/4`). The stage doubles as the preview:
sample mode substitutes sample text and `StagePlaceholder.data_url/0` for
image slots; raw mode substitutes nothing.

### Schemas and stored document

- `phoenix_kit_og_templates` — `name` (unique:
  `phoenix_kit_og_templates_name_uniq`, ≤ 255), `description` (≤ 1024),
  `canvas` JSONB, optional `preview_image_uuid`.
- `phoenix_kit_og_assignments` — `module_key` (≤ 64), `scope_type` (≤ 32),
  `scope_uuid` (nullable), `template_uuid` (FK, CASCADE), `slot_mapping` JSONB
  — a flat `%{slot_name => variable_name}` of strings only (nested shapes are
  rejected so consumer-specific structure never leaks into storage).

The `canvas` column holds an OpenFresco scene (`Scene.to_map/1`):
`%{"version" => "1", "canvas" => %{"width", "height", "background"},
"elements" => [...]}` with element kinds text / image / shape / button /
stamp, fills solid / gradient / image, optional per-element `anchor`
(`%{to, edge, gap, align}`) and `mask` — see `OpenFresco.Scene` for the full
shapes. Legacy editor canvases (`%{"width", "height", "background",
"elements"}` with `x/y/width/height` per element and no `"version"` key) still
load: `SceneStore.load/1` converts them through `OpenFresco.OgImport` on read
and the next editor save persists the scene form. A nil, empty or corrupt
canvas loads as `SceneStore.blank/0` (1200×630, dark background) — rendering
never crashes on a malformed row.

### Settings, permissions, PubSub

- Settings: `phoenix_kit_og_enabled` (boolean, default off). Reads
  `project_title` for `[[site_name]]`.
- Permission key `phoenix_kit_og` (`permission_metadata/0`); all three tabs
  require it. No sub-permissions.
- PubSub: none.

## Database & migrations

None. Tables `phoenix_kit_og_templates` and `phoenix_kit_og_assignments` ship
in core's chain (core V154, above the V135 baseline); `migration_module/0` is
unset. A schema change is a core migration first (plus core's
`ExpectedSchema`), then schema edits here. Assignment uniqueness is a partial
index pair because Postgres treats NULL as distinct: one row per
`(module_key, scope_type)` where `scope_uuid IS NULL`, one per full triple
otherwise. UUIDv7 PKs; `use PhoenixKit.SchemaPrefix` on both schemas.

## Testing

- Test DB `phoenix_kit_og_test` (+ `MIX_TEST_PARTITION`). `config/test.exs`
  honours `PGUSER` / `PGPASSWORD` / `PGHOST` (defaults `postgres` /
  `postgres` / `localhost`).
- `test_helper.exs`: checks the DB exists via `psql -lqt`, starts
  `PhoenixKitOG.Test.Repo`, installs `uuid-ossp` + a `uuid_generate_v7()`
  function, runs `PhoenixKit.Migration.ensure_current/2`, then checks
  `phoenix_kit_og_templates` exists. Without a DB or without the tables it
  excludes `:integration` with a hint. It also starts `PhoenixKit.PubSub.Manager`,
  `PhoenixKit.ModuleRegistry`, and (DB + tables only) `PhoenixKitOG.Test.Endpoint`;
  sets the url prefix to `/`; installs a logger filter that drops "Failed to
  query setting" OwnershipError noise from background settings reads (core
  returns the default; log spam, not a failure).
- Support: `PhoenixKitOG.DataCase` (sandbox owner, `:integration`),
  `PhoenixKitOG.LiveCase` (`:integration`, `@endpoint Test.Endpoint`,
  `fake_scope/1` — a real `%Scope{}` with a real `%User{}`, roles as a list,
  permissions as a MapSet — and `put_test_scope/2`), `Test.Endpoint` /
  `Test.Router` (routes at `/en/admin/open-graph`, `…/assignments`,
  `…/:uuid/edit`) / `Test.Layouts` / `Test.Hooks` (`on_mount :assign_scope`
  mirrors the session scope onto `:phoenix_kit_current_scope` +
  `:phoenix_kit_current_user`, seeds `:current_locale` and `:url_path`). The
  test router applies no permission gate.
- Without Postgres: behaviour + conformance tests, Errors, Variables, Cache,
  Media, SceneStore, SceneEdit, StagePlaceholder, schema changesets,
  ImageController, render-pipeline unit tests.
- With Postgres: Templates CRUD + activity (including the `failed: true`
  row), Assignments upsert / `clear` / `update_slot_mapping`, the concurrent
  duplicate guard (`{:error, changeset}`, never a raised constraint), the
  most-specific-wins hierarchy (nil-scope skip, default fall-through, `:none`,
  slot-mapping carry), and LV mounts for the three admin pages (assignment
  modal, preview-platform tabs).
- Not yet asserted in LV tests: `phx-disable-with` presence, translated
  labels, actor-uuid threading.
- Known noise without a DB: `Settings read for "project_title" failed …
  could not lookup Ecto repo` warnings from `Variables.global_values/1`; the
  value falls back to `""`, not a failure.
- `PhoenixKitOG.enabled?/0` in the unit env falls back to `false` through the
  rescue (no DB); assert `is_boolean/1`, not a value. `function_exported?/3`
  does not load a module — `Code.ensure_loaded?/1` first, or the assertion
  flakes under seed orderings.

## Feature notes

None. Feature behaviour is documented in `@moduledoc`s; the open_fresco design
record is `dev_docs/fresco_feature_checklist.md`,
`dev_docs/fresco_editor_renderer_requirements.md` and
`dev_docs/open_fresco_feedback_todo.md`.

## Versioning & releases

SemVer. The version is single-sourced in `mix.exs` (`@version`); `version/0`
reads it at compile time and the behaviour test asserts against
`Mix.Project.config()[:version]`, so nothing else needs bumping.

Release procedure (the steps the maintainer runs):

1. Bump `@version` in `mix.exs`; add a `CHANGELOG.md` entry headed `## x.y.z - YYYY-MM-DD`.
2. `mix precommit` clean.
3. Commit (`"Bump version to x.y.z"`) and push; verify the push landed.
4. `mix hex.publish`.
5. Tag, matching the form of the newest existing tag (`git tag --sort=-creatordate | head -1` shows it), and push the tag.
6. GitHub release via `gh release create` if the repo does those (`gh release list` shows whether it does).

Tags are immutable pointers: never tag before the commit is pushed and the
publish has succeeded.

## Pull requests & commits

- Commit messages start with an action verb (`Add`, `Update`, `Fix`, `Remove`, `Merge`). No AI attribution and no `Co-Authored-By` trailers.
- Version bumps and CHANGELOG entries land with the release commit on upstream, not in feature PRs.
- Review files live in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/{AGENT}_REVIEW.md`, one file per reviewing agent, never edited by another agent; `FOLLOW_UP.md` records how each finding was resolved. Severities: `BUG - CRITICAL/HIGH/MEDIUM`, `IMPROVEMENT - HIGH/MEDIUM`, `NITPICK`.

`dev_docs/pull_requests/README.md` has the full convention and
`dev_docs/pull_requests/TEMPLATE.md` the PR summary template.

## TODOs

- **i18n long-tail** — the common UI strings are translated in all 7
  locales; the deep editor property/hint strings ride as English fallback
  pending a translation pass.
- **`js_sources/0` carries no `@impl`** — the annotation was left off while
  the resolved core predated the callback; core `~> 2.0` ships it, so add
  `@impl PhoenixKit.Module` the next time the file is touched and confirm
  `--warnings-as-errors` stays clean.
