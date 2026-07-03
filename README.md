# PhoenixKitOG

OpenGraph template + hierarchical assignment module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit).

Build OG preview-card images (`og:image`) from a WYSIWYG canvas editor,
assign templates per-scope (e.g. per post, per group, or a module-wide
default), and render them to PNG on demand — instead of hand-designing a
static image for every page.

## Features

- **Template editor** — SVG canvas with text, image, rect, and stamp
  elements; `{{slot}}` variables a consumer wires up, `[[global]]` variables
  resolved automatically (site URL, host, name, page URL, locale)
- **Hierarchical assignments** — bind a template to a scope inside a
  consumer's hierarchy (e.g. `post → group → default`); first match wins
- **Rendering** — SVG → PNG via the `:resvg` NIF (with CLI fallbacks),
  disk-cached by content hash
- **Safe by default** — a kill switch and pass-through-on-error seam mean a
  broken template or missing rasterizer never crashes a public page render
- **Zero-config discovery** — implements `PhoenixKit.Module`; the host app
  finds it automatically, no wiring required

## Installation

Add `phoenix_kit_og` to your `mix.exs` deps, alongside `phoenix_kit` itself:

```elixir
def deps do
  [
    {:phoenix_kit, "~> 1.7"},
    {:phoenix_kit_og, "~> 0.1"}
  ]
end
```

Then `mix deps.get`. PhoenixKit's module auto-discovery picks it up on next
boot — no config or router changes needed. Enable it from the PhoenixKit
admin dashboard (OpenGraph tab), which flips the `phoenix_kit_og_enabled`
setting.

Rendering prefers the precompiled `:resvg` NIF (already a dependency); if
that NIF can't load on your host, it falls back to the `resvg` CLI,
`rsvg-convert`, or ImageMagick — install one of those as a system package if
you're on an unusual target.

## Quick start

1. In the admin dashboard, open **OpenGraph → Templates** and design a
   canvas (add text/image/rect elements, wire `{{slot}}` placeholders).
2. Open **OpenGraph → Assignments** and bind the template to a scope (e.g. a
   specific post, a group, or the module-wide default).
3. A consumer module calls `PhoenixKitOG.refine_og/4` from its own OG-tag
   rendering path; when a template resolves, the rendered PNG URL replaces
   the consumer's `og:image`.

## Usage — wiring up a consumer module

Any module can plug in by implementing two optional callbacks on its own
`PhoenixKit.Module`:

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

`og_variables/0` declares what a template author can bind a slot to;
`og_resolve/2` fetches the actual value at render time. Then, wherever the
consumer builds its OG tag map:

```elixir
og = %{title: post.title, description: post.excerpt, image: post.image_url, ...}
og = PhoenixKitOG.refine_og(og, conn, post, language)
```

When the module is disabled, no template resolves, or resolution raises,
`refine_og/4` returns `og` unchanged — the consumer's own OG image keeps
working either way.

`phoenix_kit_publishing` is the reference consumer; see its
`Web.Controller.build_og_data/4` for a complete integration.

## Architecture

See [AGENTS.md](AGENTS.md) for the full architecture: variable syntax and
resolution order, hierarchy resolution semantics, the rendering pipeline and
cache, canvas element JSON shapes, and the editor's JS hook.

## Development

```bash
mix deps.get                # Install dependencies
mix test                     # Run the test suite
mix format                   # Format code
mix credo --strict           # Static analysis
mix dialyzer                 # Type checking
mix precommit                # compile (warnings-as-errors) + deps.unlock --check-unused + quality.ci
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `phoenix_kit` | Module behaviour, Settings API, admin dashboard integration |
| `phoenix_live_view` | Template/assignment editor LiveViews |
| `ecto_sql` | Template and assignment schemas |
| `resvg` | SVG → PNG rasterization (precompiled NIF) |

## License

MIT — see [LICENSE](LICENSE) for details.
