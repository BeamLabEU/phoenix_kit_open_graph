defmodule PhoenixKitOG.Render.Cache do
  @moduledoc """
  On-disk cache for rendered OG PNGs.

  Cache key = SHA-256 of `(template_uuid, template_updated_at, canvas,
  binding_values)`. Two different posts with the same resolved values
  share a single file; editing the template invalidates every dependent
  cache entry automatically (the template's `updated_at` is part of the
  key).

  Files live under `System.tmp_dir!()/phoenix_kit_og_cache/` — a writable,
  ephemeral scratch dir (NOT `priv/static`, which is read-only in a release),
  read back by `PhoenixKitOG.Web.ImageController` at `/og-image/:key` and
  streamed as `image/png`. Filename pattern:

      <16-hex hash>.png

  The full hash is 64 hex; we truncate to 16 (64 bits) which is
  collision-resistant for our scale (millions of templates × posts).
  """

  # Deliberately NOT under `priv/static/` — the dev live-reload plug
  # watches `priv/static/*.png` and would restart the LiveView every
  # time we cache a render (which then wipes any modal state that
  # depended on the fresh URL).
  @subdir "phoenix_kit_og_cache"

  @doc """
  Returns `{cache_key, absolute_path}`. The path may or may not exist —
  call `exists?/1` or `read/1` to check.
  """
  @spec key_and_path(map(), map()) :: {String.t(), String.t()}
  def key_and_path(template, context) do
    key = hash(template, context)
    {key, path_for_key(key)}
  end

  @spec exists?(String.t()) :: boolean()
  def exists?(key), do: File.exists?(path_for_key(key))

  @spec read(String.t()) :: {:ok, binary()} | {:error, term()}
  def read(key), do: File.read(path_for_key(key))

  @doc """
  Writes the PNG bytes to the cache file. Atomic: write to a tempfile
  in the same dir then rename, so a concurrent read never sees a
  partial file.
  """
  @spec write(String.t(), binary()) :: :ok | {:error, term()}
  def write(key, png_bytes) when is_binary(png_bytes) do
    path = path_for_key(key)
    File.mkdir_p!(Path.dirname(path))

    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(tmp, png_bytes),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end

  @doc "Clears every cached render — useful after upgrading the renderer."
  @spec clear() :: :ok
  def clear do
    base = base_dir()
    if File.dir?(base), do: File.rm_rf!(base)
    File.mkdir_p!(base)
    :ok
  end

  # =========================================================================
  # Internals
  # =========================================================================

  @spec hash(map(), map()) :: String.t()
  defp hash(template, context) do
    payload = %{
      "template_uuid" => template.uuid,
      "template_updated_at" => to_string(template.updated_at),
      "canvas" => template.canvas,
      "values" => Map.get(context, :values, %{}),
      "module_key" => Map.get(context, :module_key)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(payload, [:deterministic]))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp path_for_key(key) do
    Path.join([base_dir(), "#{key}.png"])
  end

  defp base_dir do
    # Prefer an explicit override for tests / hosts that want a
    # different cache location. Otherwise sit under `System.tmp_dir!()`
    # — deliberately NOT `priv/static/` because the dev live-reload
    # plug watches those files and would restart the LiveView on
    # every render.
    Application.get_env(:phoenix_kit_og, :cache_dir) ||
      Path.join(System.tmp_dir!(), @subdir)
  rescue
    _ -> Path.join(System.tmp_dir!(), @subdir)
  end
end
