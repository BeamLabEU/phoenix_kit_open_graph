# Changelog

All notable changes to this project will be documented in this file.

## 0.4.0 - 2026-11-13

### Changed

- **Core pin widened to `>= 2.65.0 and < 4.0.0`:** works with core 3.x (core 3.0 stops creating the module tables; this module's own chain builds its tables). The floor is the first core with the `file_references/0` and `expected_schema/0` callbacks, which now carry `@impl PhoenixKit.Module`.

### Added

- **The module supplies the manifest of its 1 tables** (`expected_schema/0`, `PhoenixKitOG.ExpectedSchema`), so `mix phoenix_kit.repair` and `mix phoenix_kit.doctor` check and repair them again, now from the module's own chain instead of core's manifest. Generated from `PhoenixKitOG.Migrations` by core's `dev_docs/squash/generate_module_manifest.exs`, never edited by hand. Core uses it from the first release after 2.64.1; before that nothing reads it. Repair is additive (it creates what is missing and reports the rest) and checks the tables only while the database is at the chain's current version. No migration.

## 0.3.9 - 2026-10-13

### Fixed

- Deleting a template audits exactly the assignments it removed: they are
  deleted in the same transaction with `DELETE … RETURNING`, so an assignment
  a concurrent transaction moved to another template is no longer logged as
  deleted.
- `Assignments.update/4` returns an error (and the assignments page shows its
  not-found flash) when the row was removed since it was loaded, instead of
  raising `Ecto.StaleEntryError`.
- A shape with an image fill no longer shows OpenFresco's stand-in on a public
  card: an unresolved or remote fill drops the shape, and a static media UUID
  in the fill is inlined like any other image.

## 0.3.8 - 2026-10-13

### Added

- **Assignments** (#14): `Assignments.create/6` (refuses a scope that already
  has an assignment), `update/4` (saves the row it opened; scope is not an
  input), `get_by_uuid/1`, `list_for_template/1`, `count_by_template/0`.
  The admin Edit modal locks scope and group; New points at the existing
  assignment's Edit instead of replacing it.
- The templates list's delete confirmation states how many assignments go
  with the template.
- `[[global]]` entries in the editor's insert menu show their label and
  description.

### Changed

- **Honest public cards.** A wired slot with no value renders as nothing
  rather than `{{Description}}`; a remote http(s) image is left off the card
  (never a stand-in), and the assignments UI refuses a remote URL for an image
  slot. `[[site_url]]`, `[[site_host]]` and `[[page_url]]` come from the
  configured origin (`:canonical_host_resolver`, the `site_url` setting, the
  endpoint URL), never the request's `Host` header.
- `/new` creates the template on its connected mount and navigates to
  `/:uuid/edit`, so a reconnect no longer creates a second template; a taken
  "Untitled N" name moves on to the next number.
- `refine_og/4` also survives an exit, logs identifiers only, and resolves
  the post's group slug to the group uuid for the group tier.
- The render cache key hashes only the globals a scene references and no
  longer includes the module key, so every PNG cached before this release is
  re-rendered once.
- Deleting a template writes one `assignment.deleted` activity row per
  cascaded assignment, in the delete's transaction.
- A typed variable name is normalised to letters, digits and underscores.
- Every `phx-change` form also carries `phx-submit`; the template name
  commits on blur or Enter.
- The JS bundle now carries only the keyboard hook; pointer gestures belong
  to `open_fresco`.

### Fixed

- Backspace in a focused dropdown no longer deletes the selected element.
- `Templates.delete/2` returns `{:error, :not_found}` for a template another
  admin already deleted, instead of raising `Ecto.StaleEntryError`.

## 0.3.7 - 2026-09-25

### Changed

- **Actor and activity logging through core** (#13). The three admin
  LiveViews read the actor with core's `PhoenixKitWeb.Actor.opts/1` (scope
  first, bare user as fallback) instead of a private helper each, and
  `PhoenixKitOG.ActivityLog` calls `PhoenixKit.Activity.log/3`, which never
  raises, in place of its own guards.
- The core pin is now `>= 2.38.0 and < 3.0.0`, the first core carrying
  `PhoenixKitWeb.Actor` and `Activity.log/3`; the conformance test enforces
  the compound form.
- `js_sources/0` carries `@impl PhoenixKit.Module`.
- The admin header renders a section / crumb / title trail: "OpenGraph" as
  the section on every page, "Assignments" and "Edit" (under the template's
  name) or "New template" as titles.
- Dependency lock: `phoenix_kit` 2.40.1, plus routine bumps.

### Fixed

- Post-merge: opening `/admin/open-graph/new` logged an unattributed
  `template.created`; the insert now carries the signed-in actor.
- Post-merge: a failed write logs through core's `Activity.log_failed/3`, so
  the row carries core's `db_pending` marker and triggers no notification
  fan-out. The `failed` / `reason` metadata stays.
- Post-merge: "New template", now the editor's header title, is translated
  in all 7 locales.

## 0.3.6 - 2026-09-17

### Added

- **Module-owned migrations** (#12). `migration_module/0` now returns
  `PhoenixKitOG.Migrations`, so `mix phoenix_kit.update` picks the module
  up. V1 is pure adoption of the two tables core's V154 still creates:
  `CREATE TABLE IF NOT EXISTS` plus catalog-shape guards for the primary
  keys, the name UNIQUE constraint, the FK and the 3 indexes (safe on a
  host that renamed tables or objects), a DROP-first self-heal for an
  invalid canonically named index, and a `pkog_schema:1` marker comment
  on `phoenix_kit_og_templates`. Nothing observable changes; `down/1`
  never drops a table. README gains a "Removing this module" section.
- `Template.column_widths/0` and `Assignment.column_widths/0`, the single
  source for the varchar widths the migration DDL uses.

### Changed

- Dependency lock: `phoenix_kit` 2.13.6 → 2.28.1, plus routine bumps.

### Fixed

- Post-merge: the invalid-index migration tests fake a crashed build with
  `UPDATE pg_index`, which only a superuser may run, so they failed under
  an ordinary test role. They are now tagged `:requires_superuser` and
  excluded when the role lacks `rolsuper`.

## 0.3.5 - 2026-08-22

### Changed

- **The preview-platform switcher is core's `<.nav_tabs>`** instead of a
  hand-rolled `tabs-box` strip. Event tabs dispatch `phx-value-tab`, so
  the handler now matches `%{"tab" => _}` rather than `%{"platform" =>
  _}` (#10). The nine property-panel segmented controls stay radio
  inputs in `phx-change` forms — they are not tabs.

- Dependency lock: `phoenix_kit` 2.13.5 → 2.13.6. This call site uses
  the event-tab API that already shipped in 2.13.5 (`on_change` +
  `phx-value-tab`); it does not need `:border` or verbatim `:patch`.

### Fixed

- Post-merge: `class="tabs-sm p-0.5"` was appended to boxed's baked-in
  `p-1`. `class` can only add, so the two padding utilities fought
  (stylesheet order, not HTML order — `p-1` wins). Dropped `p-0.5` and
  kept `tabs-sm`. Tab ids are now maps at the source, matching every
  other event-tab strip.

### Added

- Regression tests for the payload-key contract: a source-level guard
  that the template is `<.nav_tabs>` matching `%{"tab" => _}` and that
  `platform_tabs/0` ids stay in sync with `@preview_platforms`, plus a
  LiveView click that wraps the stage in Facebook chrome and proves the
  old `%{"platform" => _}` payload is a silent no-op.

## 0.3.4 - 2026-08-21

### Fixed

- **Every editor `phx-change` form now has an `id`**, so LiveView form
  recovery actually works on the canvas — the same gap 0.3.3 closed for
  the three scope/group/template forms (#9).
- **daisyUI 4 `tabs-boxed` → v5 `tabs-box`** on the editor's segmented
  controls. These stay radio inputs in a form, not core's `<.nav_tabs>`
  (#9).
- Post-merge: two canvas form ids named for the wrong field
  (`og-canvas-size-form` was `bg_type`; `og-canvas-bg-type-form` was
  `bg_image_fit`) plus the button style strip (`preset`, not align).

## 0.3.3 - 2026-08-14

### Fixed

- **The assignment modal crashed with `KeyError :preview_loading` as soon as a
  template was picked**, which made the assignments screen unusable end to end:
  an assignment cannot be saved without choosing a template, and choosing one is
  what crashed. `edit_modal/1` is a function component, so `@preview_loading` in
  its body reads *that component's* assigns — and it was neither declared as an
  `attr` nor passed at the call site. Both are now in place (#8, #7).

  It survived four releases because the read sits behind
  `:if={@selected_template}`, and HEEx wraps the whole component invocation —
  attribute expressions included — in that conditional, so the modal rendered
  fine until a template was picked. Nothing warns at compile time.

- **The three scope/group/template forms had no `id`.** A `phx-change` form
  without one silently disables LiveView form recovery.

### Added

- **LiveView test plumbing** (`test/support/{live_case,test_endpoint,test_hooks,
  test_layouts,test_router}.ex`) — this package had none, so nothing could
  render a LiveView under test. Plus a regression guard pinning the invariant
  the bug broke: `edit_modal/1` reads no assign it neither declares nor assigns,
  and the call site passes `preview_loading` through (the attr defaults to
  `false`, so a dropped pass-through would otherwise kill the spinner silently).

### Changed

- Dependency updates: `phoenix_kit` 2.4.0. The `~> 2.0` pin is unchanged —
  nothing here uses core's new `Slug.put_slug/3`.

## 0.3.2 - 2026-08-11

### Changed

- Dependency updates: `phoenix_kit` 2.2.0 and the transitive set it pulls
  (`phoenix` 1.8.10, `hackney` 4.7.3). No source changes in this package.

## 0.3.1 - 2026-08-11

### Added

- **A conformance test for the `:phoenix_kit` requirement** (#6). The pin is a
  contract with consumers and nothing here exercised it: a host depending on
  both this module and a core version the requirement excludes gets an
  unsolvable dependency set and `mix deps.get` fails outright, while this
  repo's own suite stays green. The specific trap is the three-segment form —
  `~> 2.0.x` expands to `< 2.1.0`, so no core 2.1 satisfies it.

  The check reads the resolved dep first and falls back to the committed
  literal in `mix.exs`, so it stays meaningful under the `PHOENIX_KIT_PATH`
  override while still failing when a `path:` dep is genuinely committed.

## 0.3.0 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

### Added

- **Any module can render an OG image (PR #5).** `PhoenixKitOG.og_image_url/5`
  is now the generic entry point; the previous publishing-only coupling lived in
  the call shape, not in anything essential. Scene storage plus the OpenFresco
  editor and renderer sit behind it.

### Changed

- **`mix precommit` passes again.** It had been failing on `main` — 22 credo
  findings, unchanged since well before this release. Cleared all 22: missing
  aliases for nested modules, six too-deeply-nested function bodies extracted
  into named helpers, and four over-complex dispatch functions in `SceneEdit`
  (`update_element/4`, `update_canvas/3`, `set_anchor/4`, `insert/2`) re-shaped
  from wide `cond`/`case` blocks into function clauses over the same keys. All
  behaviour-preserving; `scene_edit_test.exs` passes throughout.
- Clearing credo let dialyzer run for the first time (`quality.ci` halts at the
  first failure). Six findings surfaced, none a defect — two are artifacts of
  the optional PNG rasterizer backend being absent in this package's own
  environment, four are defensive clauses dialyzer can prove dead from today's
  callers. Recorded in a new `.dialyzer_ignore.exs`, each with its reason.
- The optional calls into `phoenix_kit_publishing` use `apply/3` so dialyzer
  does not report `unknown_function` for a peer that is not a dependency. The
  runtime guards (`Code.ensure_loaded?` + `function_exported?` + `rescue`) are
  unchanged and remain the real contract.

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
