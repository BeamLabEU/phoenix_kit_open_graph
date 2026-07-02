# AGENTS.md — phoenix_kit_og

OpenGraph composition module for PhoenixKit. Templates + hierarchical
assignment + (Phase 3) image rendering. Other modules call `refine_og/4`
through the seam already in `phoenix_kit_publishing/web/controller.ex`.

## Architecture

### Hierarchy of resolution

Each consumer module declares its scope hierarchy, most-specific first.
Publishing's hierarchy:

```
post → group → publishing-module-default
```

`PhoenixKitOg.resolve_template/2` walks the list, returns the first
assignment that matches. A consumer simply passes:

```elixir
PhoenixKitOg.resolve_template("publishing", [
  {"post", post.uuid},
  {"group", group.uuid},
  {"default", nil}
])
```

### Schemas

- `phoenix_kit_og_templates` (V139, core)
  - `uuid`, `name`, `description`
  - `canvas` JSONB — `%{"width" => 1200, "height" => 630, "elements" => […]}`
  - `preview_image_uuid` (optional pointer to a rendered cached image)
- `phoenix_kit_og_assignments` (V139, core)
  - `uuid`, `module_key` (string), `scope_type` (string), `scope_uuid` (UUID nullable)
  - `template_uuid` (FK → templates, ON DELETE CASCADE)
  - Unique: `(module_key, scope_type, COALESCE(scope_uuid, '00000000-0000-0000-0000-000000000000'))`

### Canvas JSON shape

```json
{
  "width": 1200,
  "height": 630,
  "background": {"type": "color", "value": "#0b1220"},
  "elements": [
    {"type": "text", "x": 60, "y": 80, "binding": "{post.title}",
     "font": "Inter", "size": 64, "color": "#ffffff", "weight": 700},
    {"type": "image", "x": 1080, "y": 540, "width": 80, "height": 80,
     "src": "media:018e3c4a-…"},
    {"type": "stamp", "preset": "site_url",
     "x": 60, "y": 560, "color": "#94a3b8", "size": 24}
  ]
}
```

### Variable bindings

Substitution happens at render time. Consumers pass a context map; the
template's `{binding}` strings are looked up. Publishing supplies:

- `{post.title}`, `{post.description}`, `{post.url}`, `{post.author}`
- `{site.host}`, `{site.url}`, `{site.name}`

Missing bindings render as empty string (no crash).

## Phases

- **Phase 1** (this commit): schemas, contexts, admin Templates list +
  Assignments tree, `refine_og/4` walks hierarchy and returns input
  unchanged when no template / no renderer.
- **Phase 2**: SVG canvas template editor.
- **Phase 3**: Server-side image render (resvg → PNG) + caching.
- **Phase 4**: Per-group set-template UI inside publishing.

## Commit conventions

Start commit subjects with action verbs (`Add`, `Update`, `Fix`,
`Remove`, `Merge`). **Do not add `Co-Authored-By: Claude`** lines — this
matches every other `phoenix_kit_*` module.

## Development

Run `mix` from `/www/app/`, not from inside this plugin subdir (deps
live in the parent's `_build`). Exception: `mix format`.

```bash
# In /www/app:
mix compile
sudo supervisorctl restart elixir
```

## CSS / JS

UI surfaces register `:phoenix_kit_og` via `css_sources/0` so Tailwind
scans this plugin's templates. The parent's `assets/css/app.css`
`@source` list must include `/www/phoenix_kit_og/lib` once.

External modules can't ship JS through the parent's pipeline — inline
`<script>` in templates, register hooks on `window.PhoenixKitHooks`.
