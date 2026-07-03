defmodule PhoenixKitOg.Render.Placeholder do
  @moduledoc """
  Stand-in image for previews and any other spot that needs a
  reference visual when a real image slot is unresolved.

  Ships as a data URL — no static file serving to configure, and it
  works everywhere `<image href="…">` accepts a `data:` scheme
  (browsers, resvg, and every rasterizer we use).

  The design is intentionally boring — a light-gray square with four
  arrows radiating from the center to the corners, plus a small
  "Placeholder image" caption. Zero brand, zero color, zero risk of
  being mistaken for real content.
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
end
