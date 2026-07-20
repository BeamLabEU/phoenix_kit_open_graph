defmodule PhoenixKitOG.Render do
  @moduledoc """
  Top-level rendering facade. Given a template + binding values,
  produces a PNG (cached) and returns its public URL.

  Pipeline:

      template + context  ─►  cache lookup
                              │
                              ├── hit ──►  served path
                              │
                              └── miss ──► SVG generation
                                           rasterize (resvg NIF,
                                             CLI/ImageMagick fallbacks)
                                           atomic write to cache
                                           served path

  When the rasterizer isn't installed (`:rasterizer_missing`), the
  caller (`PhoenixKitOG.refine_og/4`) is expected to drop back to the
  pre-existing `og.image` — never a crash.
  """

  require Logger

  alias PhoenixKitOG.Render.{Cache, Rasterizer, Svg}
  alias PhoenixKitOG.Schemas.Template

  @doc """
  Returns `{:ok, public_url}` on success, `{:error, reason}` on
  failure. Side effect: caches the PNG on disk so the next call is a
  no-op.
  """
  @spec render_url(Template.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def render_url(%Template{} = template, context) do
    {key, _path} = Cache.key_and_path(template, context)

    if Cache.exists?(key) do
      {:ok, cache_url(key)}
    else
      render_and_cache(template, context, key)
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

  defp render_and_cache(template, context, key) do
    svg = Svg.to_binary(template.canvas, context)

    case Rasterizer.render(svg,
           width: Map.get(template.canvas, "width", 1200),
           height: Map.get(template.canvas, "height", 630)
         ) do
      {:ok, png_bytes} ->
        case Cache.write(key, png_bytes) do
          :ok ->
            {:ok, cache_url(key)}

          {:error, reason} = err ->
            Logger.warning("[PhoenixKitOG.Render] cache write failed: #{inspect(reason)}")
            err
        end

      {:error, :rasterizer_missing} ->
        Logger.warning(
          "[PhoenixKitOG.Render] rsvg-convert not installed. " <>
            "Install librsvg2-bin (Debian/Ubuntu) to enable OG image rendering. " <>
            "Falling back to the consumer's derived image."
        )

        {:error, :rasterizer_missing}

      {:error, reason} = err ->
        Logger.warning("[PhoenixKitOG.Render] rasterize failed: #{inspect(reason)}")
        err
    end
  end
end
