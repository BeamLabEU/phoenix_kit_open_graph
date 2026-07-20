# AGENTS.md — phoenix_kit_og

OpenGraph template + hierarchical assignment plugin for PhoenixKit.
Ships:

- **Templates** — WYSIWYG SVG canvas editor for OG image designs
  (text + image + rect + stamp elements, `{{slot}}` and `[[global]]`
  variable syntax).
- **Assignments** — bind a template to a scope inside a consumer
  module's hierarchy (`post → group → default`). Admin modal for CRUD
  + live preview against a real published post.
- **Renderer** — SVG → PNG via the `:resvg` NIF. Cached on disk keyed
  by (template, canvas, values). Consumer modules integrate through
  the `refine_og/4` seam.

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
otherwise. See V152.

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
Pipeline: cache lookup by SHA-256 of `(template_uuid, updated_at,
canvas, values, module_key)` → SVG generation → rasterize.

- **SVG** — `Render.Svg.to_binary/2` walks the canvas, substitutes
  slot values, emits `<image>` / `<text>` / `<rect>`. Text picks up
  a `DejaVu Sans, Liberation Sans, Arial, sans-serif` fallback so it
  renders even when the picked font isn't installed on the host.
- **Media UUIDs** — resolved to local file bytes and inlined as
  `data:image/*;base64,…` URLs. The rasterizer runs locally and
  can't fetch remote HTTP; inlining sidesteps that. Falls back to
  the storage public URL only when local bytes aren't reachable.
- **Rasterizer** — prefers `:resvg` NIF (`Hex :resvg`), falls back
  to `resvg` CLI, `rsvg-convert`, or ImageMagick. Reports
  `{:error, :rasterizer_missing}` when nothing is reachable; the
  seam pass-through then keeps publishing's fallback image.
- **Cache** — `System.tmp_dir!()/phoenix_kit_og_cache/<key>.png`.
  Under `System.tmp_dir!()` deliberately: `priv/static/` triggers
  the dev live-reload plug on every render and wipes modal state.
- **Serving** — `GET /phoenix_kit/og-image/:key` (see
  `Web.ImageController`). `image/png` content-type without the
  default `; charset=utf-8` suffix (Telegram drops previews when
  a binary MIME carries a text charset). Cache-control public,
  30-day, immutable.

### Schemas

- `phoenix_kit_og_templates` (V152) — `name`, `description`,
  `canvas` JSONB (`%{"width", "height", "background", "elements"}`),
  optional `preview_image_uuid`.
- `phoenix_kit_og_assignments` (V152) — `module_key`, `scope_type`,
  `scope_uuid` (nullable), `template_uuid` (FK CASCADE),
  `slot_mapping` JSONB (`%{slot_name => variable_name}`).

### Canvas element shapes

```json
{
  "width": 1200,
  "height": 630,
  "background": {
    "type": "image", "value": "{{BackgroundImage}}",
    "fit": "fill", "overlay_color": "dark", "overlay_opacity": 0.3
  },
  "elements": [
    {"type": "text", "id": "…", "x": 60, "y": 80,
     "text": "{{Text}}", "font": "Inter", "size": 64,
     "color": "#ffffff", "weight": 700,
     "underlay_color": "dark", "underlay_opacity": 0},
    {"type": "image", "id": "…", "x": 20, "y": 20,
     "width": 700, "height": 60, "src": "media-uuid or {{Image}}",
     "fit": "fill"},
    {"type": "rect", "id": "…", "x": 900, "y": 400,
     "width": 200, "height": 150, "fill": "#7adb42",
     "stroke": "#16ff0f", "stroke_width": 13, "radius": 0},
    {"type": "text", "id": "…", "text": "[[site_url]]", …}
  ]
}
```

## Editor JS hooks

The editor ships two LiveView hooks — `PhoenixKitOGCanvas` (drag/resize)
and `PhoenixKitOGEditor` (keyboard) — in a prebuilt bundle at
`priv/static/assets/phoenix_kit_og.js`, registered on
`window.PhoenixKitOGHooks`. `PhoenixKitOG.js_sources/0` declares the
bundle so core's `:phoenix_kit_js_sources` compiler folds it into the
host's single LiveSocket at construction.

**Why a bundle, not an inline `<script>`:** an inline script runs only
on a hard page load, NOT on a morphdom patch — so navigating into the
editor from the Templates list (both in `live_session
:phoenix_kit_admin`) left the hook unregistered. `js_sources/0` is the
supported path and the only one that survives LiveView navigation.

Watchdog banner: the hook sets `data-pk-og-hook-ready="true"` on
the canvas wrapper; a 2.5s timer reveals a warning when the flag
never flips (bundle didn't load, hook errored on mount, etc.).
`<noscript>` covers the JS-disabled case.

Interaction: pointerdown captures a resize handle or the drag
overlay; `evt.target.closest([data-pk-og-*-handle])` decides
which. `phx-click="deselect"` on the SVG root fires on any click
that doesn't hit an element — the hook flips
`swallowNextClick=true` on drag/resize end and a capture-phase
click listener swallows the synthetic click so the selection
isn't blown away.

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

- **DB-backed integration tests** — schema changesets are covered by
  pure tests; adding a `PhoenixKit.DataCase`-style shared setup would
  let us exercise the Assignments partial-index constraint, FK-cascade
  behavior, and the render cache under real Repo pressure.
- **LiveView smoke tests** — mount + one CRUD per LV, assert
  `phx-disable-with` presence, translated labels, actor-uuid threading.
  Blocked on a shared `LiveCase` + `Test.Endpoint` module (see the
  catalogue plugin for the reference shape).
