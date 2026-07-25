defmodule PhoenixKitOG.Render do
  @moduledoc """
  Top-level rendering facade. Given a template + binding values,
  produces a PNG (cached) and returns its public URL.

  Pipeline (since the OpenFresco switch):

      template + values/globals ─► SceneStore.load (lazy legacy-canvas
                                   migration)
                                   Media.prepare (UUIDs → data: URLs,
                                   :public fallbacks)
                                   cache lookup
                                   │
                                   ├── hit ──► served path
                                   │
                                   └── miss ─► OpenFresco.render/3
                                               (measured text, anchors,
                                               gradients, rasterize)
                                               atomic write to cache

  SVG generation, text layout, and rasterization all belong to
  `open_fresco` now; this module keeps media resolution, caching, and
  the URL contract. When no rasterizer backend is reachable
  (`:rasterizer_missing`), the caller (`PhoenixKitOG.refine_og/4`)
  drops back to the pre-existing `og.image` — never a crash.
  """

  require Logger

  alias PhoenixKitOG.Render.{Cache, Media}
  alias PhoenixKitOG.SceneStore
  alias PhoenixKitOG.Schemas.Template

  @doc """
  Returns `{:ok, public_url}` on success, `{:error, reason}` on failure.

  `context` keys:

    * `:values` — resolved `{{slot}}` values (map, required)
    * `:globals` — `[[global]]` values (map, default `%{}`)
    * `:mode` — `:public` (crawler-facing; unresolved image slots fall
      back / drop) or `:preview` (unresolved image slots draw
      OpenFresco's labeled stand-in). Default `:public`.

  Side effect: caches the PNG on disk so the next call is a no-op.
  """
  @spec render_url(Template.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render_url(%Template{} = template, context) do
    values = Map.get(context, :values, %{})
    globals = Map.get(context, :globals, %{})
    mode = Map.get(context, :mode, :public)

    {scene, values} =
      template.canvas
      |> SceneStore.load()
      |> Media.prepare(values, mode)

    cache_context = %{
      scene: SceneStore.dump(scene),
      values: values,
      globals: globals,
      module_key: Map.get(context, :module_key)
    }

    {key, _path} = Cache.key_and_path(template, cache_context)

    if Cache.exists?(key) do
      {:ok, cache_url(key)}
    else
      render_and_cache(scene, values, globals, key)
    end
  end

  @doc "Returns just the public URL for a key (whether or not it exists)."
  @spec cache_url(String.t()) :: String.t()
  # Crawlers (Facebook, Twitter, LinkedIn) sniff content-type from the
  # response header rather than the path; the URL omits `.png` because
  # Phoenix routes can't carry a literal `.png` suffix after `:key`.
  #
  # We build the URL manually rather than via `Utils.Routes.path/1`
  # because that helper injects the active locale — OG crawlers don't
  # negotiate locales and our `/og-image/:key` route lives outside the
  # localized scope. Just prepend the URL prefix.
  def cache_url(key) do
    url_prefix = PhoenixKit.Config.get_url_prefix()
    prefix = if url_prefix == "/", do: "", else: url_prefix
    prefix <> "/og-image/" <> key
  end

  # =========================================================================
  # Internals
  # =========================================================================

  defp render_and_cache(scene, values, globals, key) do
    if OpenFresco.rasterizer_available?() do
      case OpenFresco.render(scene, values, globals: globals) do
        {:ok, png_bytes, _meta} ->
          case Cache.write(key, png_bytes) do
            :ok ->
              {:ok, cache_url(key)}

            {:error, reason} = err ->
              Logger.warning("[PhoenixKitOG.Render] cache write failed: #{inspect(reason)}")
              err
          end

        {:error, reason} = err ->
          Logger.warning("[PhoenixKitOG.Render] render failed: #{inspect(reason)}")
          err
      end
    else
      Logger.warning(
        "[PhoenixKitOG.Render] no rasterizer backend reachable. " <>
          "Add {:resvg, \"~> 0.5\"} to the host app (or install resvg / " <>
          "rsvg-convert / ImageMagick) to enable OG image rendering. " <>
          "Falling back to the consumer's derived image."
      )

      {:error, :rasterizer_missing}
    end
  end
end
