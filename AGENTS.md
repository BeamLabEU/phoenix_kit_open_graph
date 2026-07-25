# AGENTS.md — phoenix_kit_og

OpenGraph template + hierarchical assignment plugin for PhoenixKit.
**Built on `open_fresco`** (alexdont's fresco-suite scene model +
editor stage + server renderer — adopted 2026-07-24, built against
this repo's `dev_docs/fresco_feature_checklist.md`). Ships:

- **Templates** — WYSIWYG editor for OG image designs. The stage is
  `OpenFresco.Editor` (server-authoritative SVG with drag/resize);
  this module owns the chrome: insert menu, property panel (text /
  image / rect / button / stamp elements, gradients, anchors), slots
  panel, always-on preview pane. `{{slot}}` and `[[global]]` variable
  syntax throughout.
- **Assignments** — bind a template to a scope inside a consumer
  module's hierarchy (`post → group → default`). Admin modal for CRUD
  + live preview against a real published post.
- **Renderer** — `OpenFresco.render/3` (measured text wrap, anchored
  layout, gradients; rasterized via the optional `:resvg` NIF with
  CLI fallbacks). Cached on disk keyed by (template, prepared scene,
  values, globals, engine versions). Consumer modules integrate
  through the `refine_og/4` seam.

**Scene storage:** the template `canvas` JSONB column now holds an
OpenFresco scene map (`%{"version" => _, "canvas" => _, "elements" =>
_}`). Legacy editor-canvas maps (no `"version"` key) still load —
`PhoenixKitOG.SceneStore.load/1` lazily converts them via
`OpenFresco.OgImport`; the next editor save persists the scene form.
No DB migration involved.

**What stays this module's:** slot wiring + assignment hierarchy,
media-UUID → `data:` URL resolution (`Render.Media` — OpenFresco
deliberately fetches nothing), `:public` vs `:preview` render modes
(public drops unresolved image elements / falls back the background;
preview shows OpenFresco's labeled stand-ins), PNG caching + the
`/og-image/:key` route, activity logging, i18n.

Consumer today: `phoenix_kit_publishing`. Any module can plug in by
implementing the two `og_variables/0` + `og_resolve/2` callbacks
described below.

## What this module DOES NOT own

- **No standalone Phoenix app** — this is a library. Endpoint/router
  come from the host. Route helpers live in `PhoenixKitOG.Routes`.
- **No consumer-specific business logic** — the plugin knows nothing
  about posts, groups, or any consumer's data. Every variable a
  template renders comes through the consumer's `og_resolve/2`.
- **No image storage of its own** — media UUIDs resolve through
  `PhoenixKit.Modules.Storage` (core). Rendered PNGs live in
  `System.tmp_dir!()/phoenix_kit_og_cache/`, not `priv/static/` (see
  `render/cache.ex` for the reason).

## Common Commands

```bash
mix deps.get                # Install dependencies
mix test                     # Run the test suite
mix format                   # Format code
mix credo --strict           # Static analysis
mix dialyzer                 # Type checking
mix precommit                 # compile (warnings-as-errors) + deps.unlock --check-unused + quality.ci
```

Run these from `/www/app/` in the deployed dev setup (see Development
below), or from this directory directly when working standalone.

## Architecture

### Two variable syntaxes

- `{{slot}}` — a template-local *slot* the assignment wires to a
  consumer variable. Slots appear in the assignments admin as fields
  to bind. Wiring: `%{"post_title" => "post_title"}`.
- `[[global]]` — resolved automatically from the OG plugin's globals
  (site_url, site_host, site_name, page_url, page_locale). Never
  wired; never shown in the slots admin panel.

`Slots.used/1` scans `{{...}}` only. `Slots.substitute/2` handles
both. `Variables.resolve/3` walks slot mappings, prefers `custom:`
prefix values (literal), then globals, then delegates to the
consumer module's `og_resolve/2`.

### Hierarchy resolution

`Assignments.resolve_template_with_mapping/2` walks an ordered list
of `{scope_type, scope_uuid}` tuples; first assignment wins. `nil`
scope_uuid on any non-`"default"` scope is skipped (means "no id at
this tier"). Publishing's hierarchy:

```elixir
[
  {"post", post.uuid},
  {"group", post.metadata.group_uuid},
  {"default", nil}
]
```

Uniqueness at the DB level uses a partial-index pair because
Postgres treats NULL as distinct: one row per `(module, scope_type)`
when `scope_uuid IS NULL` (module-wide default), one per full triple
otherwise. See core migration V154 (in `phoenix_kit`).

### Consumer module callbacks

A module opts in by implementing two optional callbacks on its
`PhoenixKit.Module` implementation:

```elixir
def og_variables do
  [
    %{name: "post_title", type: :text, label: "Post title", description: "…"},
    %{name: "post_featured_image", type: :image, label: "Featured image"}
  ]
end

def og_resolve(var_name, context)
# context = %{module_key, resource, conn, language, page_url}
```

`og_variables/0` declares shape; `og_resolve/2` fetches values at
render time. The assignments UI filters variables by type so an
`:image` slot only shows image-typed vars.

### Refine seam

Publishing calls `PhoenixKitOG.refine_og(og_map, conn, post, lang)`
per public page render. Behavior:

- **Kill switch** — when `enabled?/0` returns false, refine_og is a
  pure pass-through. Publishing keeps its own OG image resolution.
- **Enabled + template resolves** — swaps `og[:image]` for a rendered
  PNG URL and adds `image_type` / `image_width` / `image_height` so
  publishing's meta-tag component can emit `og:image:*` size hints
  that Telegram/Facebook use to pre-size the preview card.
- **Enabled + no template** — pass-through.
- **Any error** — pass-through (rescue clause).

### Rendering

`Render.render_url/2` returns `{:ok, url}` or `{:error, term}`.
Context: `%{values:, globals:, mode: :public | :preview}`. Pipeline:
`SceneStore.load` (lazy legacy-canvas migration) → `Render.Media.prepare`
(media UUIDs → `data:` URLs; `:public` fallbacks for unresolved image
slots) → cache lookup → `OpenFresco.render/3` → atomic cache write.

- **Layout + SVG + rasterize** — all `open_fresco`'s: measured text
  wrap (server font fallback DejaVu Sans / Liberation Sans / Arial),
  anchored elements, gradients/masks, then the rasterizer chain
  (`:resvg` NIF preferred; `resvg` CLI, `rsvg-convert`, ImageMagick
  fallbacks). `{:error, :rasterizer_missing}` when nothing is
  reachable; the seam pass-through then keeps publishing's fallback
  image.
- **Media UUIDs** — `Render.Media` resolves them to local file bytes
  inlined as `data:image/*;base64,…` (OpenFresco fetches no network).
  `file://` and host-relative paths are dropped.
- **Modes** — `:public` (crawler-facing): an unresolved image element
  is dropped, an unresolved image background falls back to the dark
  solid — never a stand-in in production. `:preview` (editor +
  assignments): unresolved image slots draw OpenFresco's labeled
  stand-in.
- **Cache** — `System.tmp_dir!()/phoenix_kit_og_cache/<key>.png`.
  Key hashes the prepared scene + values + globals + our
  `@render_version` + OpenFresco's engine version, so upgrades on
  either side stop serving stale PNGs. Under `System.tmp_dir!()`
  deliberately: `priv/static/` triggers the dev live-reload plug on
  every render and wipes modal state.
- **Serving** — `GET /phoenix_kit/og-image/:key` (see
  `Web.ImageController`). `image/png` content-type without the
  default `; charset=utf-8` suffix (Telegram drops previews when
  a binary MIME carries a text charset). Cache-control public,
  30-day, immutable.

### Schemas

- `phoenix_kit_og_templates` (core V154) — `name`, `description`,
  `canvas` JSONB (`%{"width", "height", "background", "elements"}`),
  optional `preview_image_uuid`.
- `phoenix_kit_og_assignments` (core V154) — `module_key`, `scope_type`,
  `scope_uuid` (nullable), `template_uuid` (FK CASCADE),
  `slot_mapping` JSONB (`%{slot_name => variable_name}`).

### Stored document

The `canvas` column holds an OpenFresco scene
(`Scene.to_map/1`): `%{"version" => "1", "canvas" => %{"width",
"height", "background"}, "elements" => [...]}` with element kinds
text / image / shape / button / stamp, fills solid / gradient / image,
optional per-element `anchor` (`%{to, edge, gap, align}`) and `mask`.
See `OpenFresco.Scene` docs for the full shapes. Legacy pre-switch
canvases (`%{"width", "height", "background", "elements"}` with
`x/y/width/height` per element, no `"version"` key) are still loadable
— `SceneStore.load/1` migrates them via `OpenFresco.OgImport` on read.

## Editor JS hooks

Two bundles ride `PhoenixKitOG.js_sources/0` so core's
`:phoenix_kit_js_sources` compiler folds them into the host's single
LiveSocket at construction:

- `open_fresco`'s `priv/static/open_fresco.js` →
  `window.OpenFrescoHooks` — the `OpenFrescoEditor` hook, the browser
  half of the server-authoritative stage (reports pointer gestures as
  canvas-space deltas; the LiveComponent applies them via
  `OpenFresco.Editor.Ops` and re-renders).
- this repo's `priv/static/assets/phoenix_kit_og.js` →
  `window.PhoenixKitOGHooks` — the `PhoenixKitOGEditor` keyboard hook
  (nudge/delete/Ctrl+S at the LV level).

**Why bundles, not inline `<script>`s:** an inline script runs only
on a hard page load, NOT on a morphdom patch — so navigating into the
editor from the Templates list (both in `live_session
:phoenix_kit_admin`) left hooks unregistered. `js_sources/0` is the
supported path and the only one that survives LiveView navigation.

## Development

Run `mix` from `/www/app/`, not from inside this plugin subdir (deps
live in the parent's `_build`). Exception: `mix format`.

```bash
# In /www/app:
mix compile
sudo supervisorctl restart elixir
```

## CSS / JS

UI surfaces register `:phoenix_kit_og` via `css_sources/0` so
Tailwind scans this plugin's templates. The parent's
`assets/css/app.css` `@source` list must include
`/www/phoenix_kit_og/lib` once.

JS hooks ship via `js_sources/0` (see "Editor JS hooks" above) — a
prebuilt bundle in `priv/static/assets/`, folded into the host's
LiveSocket by core's compiler. Do NOT use inline `<script>` for hooks:
it fails on LiveView navigation.

## Testing

```bash
# Context/DB tests need core V154 (the OG tables) — run against LOCAL core,
# since the published pin (~> 1.7.189) predates V154:
PHOENIX_KIT_PATH=../phoenix_kit mix test

# Standalone (published core): pure/unit tests run; :integration excluded
# with a hint until core ships V154 and the pin is raised.
mix test
```

Harness (built 2026-07-20): `test/support/{test_repo,data_case}.ex` +
`config/{config,test}.exs`; `test_helper.exs` runs
`PhoenixKit.Migration.ensure_current/2` against the test DB and excludes
`:integration` when Postgres is down OR the resolved core lacks the OG
tables (`phoenix_kit_og_templates` present-check). `PhoenixKitOG.DataCase`
gives an Ecto sandbox. Covered: Templates CRUD + activity (incl. the
`failed: true` failure row), the Assignments upsert / `clear` /
`update_slot_mapping` paths, the **concurrent-set constraint guard** (a
duplicate insert returns `{:error, changeset}`, never a raised
`Ecto.ConstraintError`), and the **most-specific-wins resolution
hierarchy** (nil-scope skip, default fall-through, `:none`, slot-mapping
carry). Pure tests (Svg/Canvas/Slots/Variables/Cache/Errors) need no DB.
Still open: LiveView smoke tests (need a `Test.Endpoint`/`LiveCase`).

## Activity logging

`PhoenixKitOG.ActivityLog` wraps `PhoenixKit.Activity` (guarded by
`Code.ensure_loaded?`, rescues `Postgrex :undefined_table` on a fresh
host). `log/4` is a pipe step: it logs the success row on `{:ok, struct}`
AND a minimal failure row on `{:error, _}` (metadata `failed: true` +
a coarse reason), so an invalid create/update/delete still leaves an
audit trail. `maybe_log/3` is the direct (non-piped) form. Metadata is
PII-safe — names/counts/UUIDs only, never canvas blobs or image bytes.

## Versioning & Releases

This project follows [Semantic Versioning](https://semver.org/). Tags use
**bare version numbers** (no `v` prefix).

### Version locations

The version must be updated in **three places** when bumping:

1. `mix.exs` — `@version` module attribute
2. `lib/phoenix_kit_og.ex` — `def version, do: "x.y.z"`
3. `test/phoenix_kit_og_test.exs` — `version/0` test (asserts against
   `Mix.Project.config()[:version]`, so it always tracks `mix.exs`; bumping
   there is enough, no hardcoded string to update separately)

### Full release checklist

1. Update version in `mix.exs` and `lib/phoenix_kit_og.ex`
2. Add a changelog entry in `CHANGELOG.md`
3. Run `mix precommit` — zero warnings/errors before proceeding
4. Commit: `"Bump version to x.y.z"`
5. Push to main and **verify the push succeeded** before tagging
6. Create and push git tag: `git tag x.y.z && git push origin x.y.z`
7. Create GitHub release: `gh release create x.y.z --title "x.y.z - YYYY-MM-DD" --notes "..."`
8. `mix hex.publish --yes`

**IMPORTANT:** Never tag before all changes are committed and pushed —
tags are immutable pointers.

## Pull Requests

### Commit Message Rules

Start commit subjects with action verbs (`Add`, `Update`, `Fix`,
`Remove`, `Merge`). **Do not add `Co-Authored-By` lines** — matches
every other `phoenix_kit_*` module.

### PR Reviews

PR review files go in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/`.
Use `{AGENT}_REVIEW.md` naming (e.g. `CLAUDE_REVIEW.md`, `GEMINI_REVIEW.md`).
See `dev_docs/pull_requests/README.md` for the full convention and
`dev_docs/pull_requests/TEMPLATE.md` for the PR summary template.

## License

MIT — see [LICENSE](LICENSE) for details.

## TODOs

Deferred quality-sweep items worth picking up later:

- **LiveView smoke tests** — mount + one CRUD per LV, assert
  `phx-disable-with` presence, translated labels, actor-uuid threading.
  Blocked on a shared `LiveCase` + `Test.Endpoint` module (see the
  catalogue plugin for the reference shape). The DB half of the harness
  (Repo + sandbox + migration bootstrap) now exists — see "Testing".
- **i18n long-tail** — the common UI strings are translated in all 7
  locales; the deep editor property/hint strings ride as English
  fallback (the ecosystem norm) pending a translation pass.
