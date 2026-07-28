defmodule PhoenixKitOG.Web.StagePlaceholder do
  @moduledoc """
  The arrows stand-in image for the editor stage's sample-values mode —
  a light-gray square with four arrows radiating to the corners and a
  "Placeholder image" caption, shipped as a `data:image/svg+xml` URL.

  **Browser-only.** The stage is a real DOM, and browsers render nested
  SVG data URLs fine. Rasterizers don't (nested-SVG `<image>` support
  varies — the original "black square" bug), so this value must never
  reach the PNG pipeline: the preview pane and the public render keep
  OpenFresco's labeled stand-in for unresolved image slots.
  """

  # 400×400 scales cleanly inside any fit mode without going blurry.
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

  # Precomputed at compile time so we're not re-encoding per render.
  @data_url "data:image/svg+xml;base64,#{Base.encode64(@svg)}"

  @doc "The stand-in as a data URL for `<image href>` use in the stage."
  @spec data_url() :: String.t()
  def data_url, do: @data_url
end
