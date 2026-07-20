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

  ## Eviction

  Every template edit mints new keys (the `updated_at` is hashed in) and
  orphans the old files, so the dir grows monotonically without a bound.
  `write/2` therefore calls `maybe_prune/0` on a small fraction of writes
  (cheap amortized): it deletes files older than `@ttl_seconds` and, if
  the count still exceeds `@max_files`, the oldest beyond the cap. A
  still-valid render just re-renders on its next miss — the cache is a
  performance layer, never a source of truth. Tune via
  `config :phoenix_kit_og, cache_ttl_seconds: _, cache_max_files: _`.
  """

  # 30 days: an OG image is regenerated far more often than that, and a
  # still-hot render simply re-renders on the next miss.
  @ttl_seconds 60 * 60 * 24 * 30
  @max_files 5_000
  # Prune on ~2% of writes so a steady render load amortizes the dir scan
  # instead of paying it on every single write.
  @prune_probability 0.02

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
      maybe_prune()
      :ok
    end
  end

  @doc """
  Deletes cache files older than the TTL and, if still over the count cap,
  the oldest beyond it. Safe to call from a cron or by hand; `write/2`
  calls it probabilistically. Never raises — a prune failure must not
  break a render.
  """
  @spec prune() :: :ok
  def prune do
    base = base_dir()

    files =
      base
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".png"))
      |> Enum.map(fn name ->
        path = Path.join(base, name)

        case File.stat(path, time: :posix) do
          {:ok, %{mtime: mtime}} -> {path, mtime}
          _ -> {path, 0}
        end
      end)

    now = System.system_time(:second)

    # Age out first.
    ttl = Application.get_env(:phoenix_kit_og, :cache_ttl_seconds, @ttl_seconds)
    max_files = Application.get_env(:phoenix_kit_og, :cache_max_files, @max_files)

    {expired, fresh} = Enum.split_with(files, fn {_p, mtime} -> now - mtime > ttl end)
    Enum.each(expired, fn {p, _} -> File.rm(p) end)

    # Then cap the count, oldest-first.
    if length(fresh) > max_files do
      fresh
      |> Enum.sort_by(fn {_p, mtime} -> mtime end)
      |> Enum.take(length(fresh) - max_files)
      |> Enum.each(fn {p, _} -> File.rm(p) end)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp maybe_prune do
    if :rand.uniform() < prune_probability(), do: prune()
    :ok
  end

  defp prune_probability,
    do: Application.get_env(:phoenix_kit_og, :cache_prune_probability, @prune_probability)

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
