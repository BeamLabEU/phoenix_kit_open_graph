# Changelog

All notable changes to this project will be documented in this file.

## 0.2.1 - 2026-07-20

### Fixed
- The Hex package's `files:` list never included `priv/`, so the 0.2.0
  package shipped without `priv/static/assets/phoenix_kit_og.js` (the editor
  JS hooks bundle declared by `js_sources/0`) or `priv/gettext/` — any host
  installing from Hex (rather than a path/git dep) failed to compile with
  `js_sources/0 bundle not found`. `priv` is now included in the package.

## 0.2.0 - 2026-07-20

### Added
- Own `PhoenixKitOG.Gettext` backend + `priv/gettext` translations across 7
  locales for the common UI string set (editor long-tail strings ride as
  English fallback pending a translation pass)
- Editor JS hooks (drag/resize + keyboard) now ship via `js_sources/0` as a
  prebuilt bundle (`priv/static/assets/phoenix_kit_og.js`) instead of an
  inline `<script>` — the inline script only ran on a hard page load, so
  navigating into the editor from the Templates list left drag/resize
  unregistered
- On-disk render cache eviction — TTL + count cap, configurable via
  `:cache_ttl_seconds` / `:cache_max_files` / `:cache_prune_probability`
- `Variables.global_label/1` and `Variables.global_description/1` — the
  canonical translated label/description for each OG-owned global variable
- Failed create/update/delete actions now log a `failed: true` activity row
  (previously only successes were audited); a failed update/delete keeps its
  `resource_uuid` so the row still points at which record was targeted

### Changed
- Preview rendering (editor + assignments modal) now runs off the LiveView
  process via `start_async`/`cancel_async`, with a loading state — a
  synchronous rasterize could block the whole modal for up to the 5s backend
  timeout

### Fixed
- SVG injection — every interpolated geometry attribute and the glow-filter
  id are now escaped/sanitized; a crafted canvas can no longer break out of
  an attribute or inject markup
- Canvas `width`/`height` are clamped (`@max_dim` 4000) on both the SVG
  viewBox and the rasterizer's output buffer, preventing an oversized canvas
  from making the rasterizer allocate an unbounded pixel buffer
- Image hrefs resolving to `file://` are dropped instead of passed through —
  was a local-file-read primitive via a CLI rasterizer backend
- `Schemas.Assignment` now declares `unique_constraint/3` on its two partial
  unique indexes, so a concurrent double-save returns `{:error, changeset}`
  instead of raising `Ecto.ConstraintError` and crashing the LiveView
- Served OG images now send `X-Content-Type-Options: nosniff`
- A preview render that crashes or is superseded mid-flight no longer leaks
  an internal error tag into the flash message text

## 0.1.1 - 2026-07-04

### Fixed
- `resvg` is now an optional dependency instead of required. Every `resvg`
  release on Hex (up to 0.5.0, the latest) hard-pins `rustler_precompiled ~>
  0.8.1`, which could make `phoenix_kit_og` un-installable for a host app
  that already needs a newer `rustler_precompiled` for something else —
  version solving would fail with no way for the host app to work around it.
  `Render.Rasterizer` already falls back to the `resvg` CLI, `rsvg-convert`,
  or ImageMagick when the NIF isn't compiled in, so making it optional loses
  nothing for hosts that can't take the pin; add `{:resvg, "~> 0.5"}`
  directly in the host app to opt into the NIF fast path.

## 0.1.0 - 2026-07-04

### Added
- WYSIWYG SVG canvas editor for OpenGraph image templates — text, image, rect,
  and stamp elements, with `{{slot}}` (consumer-wired) and `[[global]]`
  (site_url, site_host, site_name, page_url, page_locale) variable syntax
- Hierarchical template assignment system (e.g. `post → group → default`);
  admin modal for CRUD plus live preview against a real published resource
- SVG → PNG rendering pipeline (`Render.render_url/2`): prefers the `:resvg`
  NIF, falls back to the `resvg` CLI, `rsvg-convert`, or ImageMagick; disk
  cache keyed by a SHA-256 of `(template, canvas, values, module_key)`
- `refine_og/4` integration seam for consumer modules — kill-switch via
  `enabled?/0`, pass-through on any resolution error or missing template so a
  public page render can never crash on OG rendering
- `preview_og_image_url/3` for consumer editors to show "what the plugin will
  produce" without swapping the live OG image
- `GET /phoenix_kit/og-image/:key` image controller — `image/png` without a
  charset suffix (Telegram drops previews on binary MIME with a text charset),
  30-day immutable cache headers, configurable cache directory
- Consumer opt-in via two callbacks on the consumer's `PhoenixKit.Module`
  implementation: `og_variables/0` (declares available variables) and
  `og_resolve/2` (fetches values at render time); first consumer wired up is
  `phoenix_kit_publishing`
- Activity logging for template and assignment CRUD
- Admin dashboard integration: OpenGraph overview tab plus Templates and
  Assignments subtabs
- `phoenix_kit_og_templates` and `phoenix_kit_og_assignments` schemas
  (migration V154), with a partial-unique-index pair so Postgres NULL
  `scope_uuid` (module-wide default) and per-scope assignments don't collide

### Fixed
- The template editor's `/new` route no longer leaks an orphaned template row
  on every fresh page load — creation is now gated on `connected?/1` since
  LiveView mounts twice (disconnected + connected) for a full page load
- `Render.Svg` no longer hardcodes `http://localhost:4000` for host-relative
  image sources (e.g. the signed local-storage fallback URL); it now degrades
  the same way any other unresolvable image href does
