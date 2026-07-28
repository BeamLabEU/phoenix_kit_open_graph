defmodule PhoenixKitOG.Render.Media do
  @moduledoc """
  Media resolution + render-mode pre-processing between the stored scene
  and `OpenFresco.render/3`.

  OpenFresco's rasterizer deliberately reads no network: image inputs
  must be `data:` URLs (or local files). Everything in this module
  exists to bridge that:

  - **Media UUIDs** (from the media picker, or a consumer's
    `og_resolve/2` returning a storage UUID) are resolved to file bytes
    via core `Storage` and inlined as `data:` URLs.
  - **`file://`** is rejected outright — a local-file-read primitive
    with no legitimate use here.
  - **Remote http(s)** passes through; the renderer skips it, matching
    the legacy pipeline's behavior.

  Render modes:

  - `:preview` — unresolved image slots stay unresolved so OpenFresco
    draws its labeled stand-in (the editor/assignments affordance).
  - `:public` — a crawler-facing card must never ship a stand-in: an
    image *element* whose slot has no value is dropped, and an image
    *background* falls back to the house dark solid — the legacy
    pipeline's exact semantics.
  """

  alias OpenFresco.Scene

  @public_bg_fallback "#0b1220"

  @doc """
  Prepares `{scene, values}` for a render: resolves media UUIDs in both,
  then applies `:public`-mode fallbacks for unresolved image slots.
  """
  @spec prepare(Scene.t(), map(), :public | :preview) :: {Scene.t(), map()}
  def prepare(%Scene{} = scene, values, mode) when is_map(values) do
    values = resolve_values(values, PhoenixKitOG.SceneStore.slots(scene))
    scene = update_in(scene.elements, &Enum.map(&1, fn el -> resolve_element(el) end))
    scene = update_in(scene.canvas, &resolve_background/1)

    scene = if mode == :public, do: apply_public_fallbacks(scene, values), else: scene

    {scene, values}
  end

  @doc """
  Resolves image-typed slot values: a value that looks like a media UUID
  becomes a `data:` URL; `data:`/http(s) pass through; `file://` and
  host-relative paths are dropped to `nil` (unresolved).
  """
  @spec resolve_values(map(), [%{name: String.t(), type: atom()}]) :: map()
  def resolve_values(values, slots) do
    image_slots = for %{name: n, type: :image} <- slots, into: MapSet.new(), do: n

    Enum.reduce(values, %{}, fn {k, v}, acc ->
      if MapSet.member?(image_slots, k) do
        case resolve_image_value(v) do
          nil -> acc
          resolved -> Map.put(acc, k, resolved)
        end
      else
        Map.put(acc, k, v)
      end
    end)
  end

  @doc """
  OpenFresco resource-resolver fun (the 0.2.0 shared stage/rasterizer
  contract): media UUIDs resolve to local file bytes; anything else is
  `:skip` so OpenFresco's deny-by-default href policy applies. Used by
  the editor stage so authors see their picked media instead of a
  stand-in — the PNG path keeps its own pre-resolution (the cache key
  must reflect the actual image bytes, since a media UUID's content can
  change under it, e.g. rotation).
  """
  @spec resolver() :: (String.t() -> {:ok, map()} | :skip)
  def resolver do
    fn ref ->
      case read_any_local_bytes(ref) do
        {:ok, bytes, mime} -> {:ok, %{data: bytes, mime: mime}}
        :error -> :skip
      end
    end
  end

  defp read_any_local_bytes(ref) when is_binary(ref) do
    Enum.reduce_while(["medium", "original"], :error, fn variant, acc ->
      case read_local_bytes(ref, variant) do
        {:ok, bytes, mime} -> {:halt, {:ok, bytes, mime}}
        :error -> {:cont, acc}
      end
    end)
  rescue
    _ -> :error
  end

  defp read_any_local_bytes(_), do: :error

  @doc """
  Resolves a single image reference. Returns the renderable value or
  `nil` when it can't be used (unresolvable UUID, `file://`,
  host-relative path, non-binary).
  """
  @spec resolve_image_value(term()) :: String.t() | nil
  def resolve_image_value("data:" <> _ = url), do: url
  def resolve_image_value("http://" <> _ = url), do: url
  def resolve_image_value("https://" <> _ = url), do: url
  def resolve_image_value("file://" <> _), do: nil
  def resolve_image_value("/" <> _), do: nil

  def resolve_image_value(uuid) when is_binary(uuid) do
    case data_url_for_uuid(uuid) do
      {:ok, data_url} -> data_url
      :error -> nil
    end
  end

  def resolve_image_value(_), do: nil

  # =========================================================================
  # Scene walking
  # =========================================================================

  # Static (non-placeholder) image element values may be media UUIDs
  # straight from the picker — inline them. Placeholders resolve via
  # the values map instead.
  defp resolve_element(%{type: :image, value: value} = el) when is_binary(value) do
    %{el | value: resolve_image_value(value)}
  end

  defp resolve_element(el), do: el

  defp resolve_background(%{background: %{type: :image, value: value} = bg} = canvas)
       when is_binary(value) do
    %{canvas | background: %{bg | value: resolve_image_value(value)}}
  end

  defp resolve_background(canvas), do: canvas

  # =========================================================================
  # Public-mode fallbacks
  # =========================================================================

  defp apply_public_fallbacks(scene, values) do
    scene =
      update_in(scene.elements, fn elements ->
        Enum.reject(elements, fn
          %{type: :image, value: value} -> unresolved_image?(value, values)
          _ -> false
        end)
      end)

    update_in(scene.canvas, fn canvas ->
      case canvas do
        %{background: %{type: :image, value: value}} ->
          if unresolved_image?(value, values) do
            %{canvas | background: Scene.solid(@public_bg_fallback)}
          else
            canvas
          end

        _ ->
          canvas
      end
    end)
  end

  defp unresolved_image?(%{placeholder: name}, values) do
    case Map.get(values, name) do
      v when is_binary(v) and v != "" -> false
      _ -> true
    end
  end

  defp unresolved_image?(nil, _values), do: true
  defp unresolved_image?("", _values), do: true
  defp unresolved_image?(_, _values), do: false

  # =========================================================================
  # Storage access (same strategy as the legacy SVG pipeline)
  # =========================================================================

  # Try each variant until one's bytes are locally readable. `medium` is
  # small enough to inline without bloating the document; `original` is
  # the fallback when no variant exists.
  defp data_url_for_uuid(uuid) do
    Enum.reduce_while(["medium", "original"], :error, fn variant, acc ->
      case read_local_bytes(uuid, variant) do
        {:ok, bytes, mime} -> {:halt, {:ok, encode_data_url(bytes, mime)}}
        :error -> {:cont, acc}
      end
    end)
  rescue
    _ -> :error
  end

  defp read_local_bytes(uuid, variant) do
    with %{file_name: file_path, mime_type: mime} <-
           PhoenixKit.Modules.Storage.get_file_instance_by_name(uuid, variant),
         {:ok, local_path} <-
           PhoenixKit.Modules.Storage.Manager.get_local_file_path(file_path),
         {:ok, bytes} <- File.read(local_path) do
      {:ok, bytes, mime || "application/octet-stream"}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp encode_data_url(bytes, mime) do
    "data:" <> mime <> ";base64," <> Base.encode64(bytes)
  end
end
