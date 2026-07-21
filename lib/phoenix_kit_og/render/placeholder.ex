defmodule PhoenixKitOG.Render.Placeholder do
  @moduledoc """
  Stand-in image for previews and any other spot that needs a
  reference visual when a real image slot is unresolved.

  The design is intentionally boring — a light-gray square with four
  arrows radiating from the center to the corners, plus a small
  "Placeholder image" caption. Zero brand, zero color, zero risk of
  being mistaken for real content.

  Two forms:

  - `data_url/0` — the artwork as a `data:image/svg+xml;base64` URL.
    This is the *sentinel value* the preview LiveViews inject for
    unwired image slots, and it renders as-is in browser contexts
    (the editor canvas handles `data:` hrefs natively).
  - `inline_svg/4` — the same artwork as native shapes fitted to a
    target rect. `Render.Svg` swaps this in whenever a substituted
    image src equals `data_url/0`, because nesting the artwork as an
    SVG-in-`<image>` data URL breaks in the rasterized pipeline:
    backend support for nested-SVG images varies (a host on
    rsvg-convert/ImageMagick can drop it entirely — the "black
    square" failure), and even resvg never applies fonts to text
    inside a nested SVG, so the caption vanished. Top-level shapes
    render identically on every backend.
  """

  # 400×400 gives a square that scales nicely inside any
  # preserveAspectRatio mode without going blurry.
  @svg """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
    <rect width="400" height="400" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="3"/>
    <g stroke="#64748b" stroke-width="6" fill="none" stroke-linecap="round">
      <line x1="200" y1="200" x2="70" y2="70"/>
      <line x1="200" y1="200" x2="330" y2="70"/>
      <line x1="200" y1="200" x2="70" y2="330"/>
      <line x1="200" y1="200" x2="330" y2="330"/>
    </g>
    <g fill="#64748b">
      <polygon points="60,60 95,60 60,95"/>
      <polygon points="340,60 305,60 340,95"/>
      <polygon points="60,340 95,340 60,305"/>
      <polygon points="340,340 305,340 340,305"/>
    </g>
    <circle cx="200" cy="200" r="10" fill="#475569"/>
    <text x="200" y="380" fill="#64748b" font-family="system-ui, sans-serif" font-size="18" text-anchor="middle">Placeholder image</text>
  </svg>
  """

  # Precompute the data URL at compile time so we're not re-encoding on
  # every render.
  @data_url "data:image/svg+xml;base64,#{Base.encode64(@svg)}"

  @doc """
  The stand-in as a data URL — drop it into any `<image href="…">`
  slot to preview what a fully-wired template would look like.
  """
  @spec data_url() :: String.t()
  def data_url, do: @data_url

  @doc "Raw SVG string, useful if you want to embed it directly."
  @spec svg() :: String.t()
  def svg, do: @svg

  # Same font chain Render.Svg puts on canvas text — the fonts a server
  # rasterizer actually has installed.
  @caption_font "DejaVu Sans, Liberation Sans, Arial, sans-serif"

  @doc """
  The stand-in drawn as native SVG shapes fitted to `{x, y, w, h}`,
  for inlining directly into an outer SVG (see the moduledoc for why
  the rasterized pipeline needs this instead of `data_url/0`).

  The gray field fills the whole rect; the arrows motif and caption
  scale with the rect's smaller dimension so any aspect ratio looks
  intentional. Returns an empty list when the rect has no visible
  area. Output is deterministic — same inputs, same bytes — because
  the render cache hashes the SVG's inputs.
  """
  @spec inline_svg(number(), number(), number(), number()) :: iodata()
  def inline_svg(x, y, w, h) when w > 0 and h > 0 do
    m = min(w, h)
    cx = x + w / 2
    cy = y + h / 2

    # Proportions of the 400×400 artwork above.
    arm = 0.325 * m
    tip = 0.35 * m
    leg = 0.0875 * m

    [
      ~s|<rect x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(w)}" height="#{fmt(h)}" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="#{fmt(0.0075 * m)}"/>|,
      ~s|<g stroke="#64748b" stroke-width="#{fmt(0.015 * m)}" fill="none" stroke-linecap="round">|,
      line(cx, cy, cx - arm, cy - arm),
      line(cx, cy, cx + arm, cy - arm),
      line(cx, cy, cx - arm, cy + arm),
      line(cx, cy, cx + arm, cy + arm),
      ~s|</g>|,
      ~s|<g fill="#64748b">|,
      corner(cx - tip, cy - tip, leg, leg),
      corner(cx + tip, cy - tip, -leg, leg),
      corner(cx - tip, cy + tip, leg, -leg),
      corner(cx + tip, cy + tip, -leg, -leg),
      ~s|</g>|,
      ~s|<circle cx="#{fmt(cx)}" cy="#{fmt(cy)}" r="#{fmt(0.025 * m)}" fill="#475569"/>|,
      ~s|<text x="#{fmt(cx)}" y="#{fmt(y + h - 0.05 * m)}" fill="#64748b" font-family="#{@caption_font}" font-size="#{fmt(0.045 * m)}" text-anchor="middle">Placeholder image</text>|
    ]
  end

  def inline_svg(_x, _y, _w, _h), do: []

  defp line(x1, y1, x2, y2),
    do: ~s|<line x1="#{fmt(x1)}" y1="#{fmt(y1)}" x2="#{fmt(x2)}" y2="#{fmt(y2)}"/>|

  # Right triangle whose corner sits at `{x, y}`, with legs running
  # `dx`/`dy` back toward the center — the arrowhead at each corner.
  defp corner(x, y, dx, dy),
    do:
      ~s|<polygon points="#{fmt(x)},#{fmt(y)} #{fmt(x + dx)},#{fmt(y)} #{fmt(x)},#{fmt(y + dy)}"/>|

  # Compact deterministic number formatting — integers stay bare,
  # floats trim to 2 decimals so coordinates don't bloat the SVG.
  defp fmt(v) when is_integer(v), do: Integer.to_string(v)

  defp fmt(v) when is_float(v) do
    t = trunc(v)
    if v == t, do: Integer.to_string(t), else: :erlang.float_to_binary(v, decimals: 2)
  end
end
