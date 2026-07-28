defmodule PhoenixKitOG.SceneStore do
  @moduledoc """
  Loads/saves `OpenFresco.Scene` documents from the template's `canvas`
  JSONB column, with lazy migration from the legacy canvas format.

  Storage strategy: the column keeps its name (`canvas`) and JSONB type;
  its *content* is now an OpenFresco scene map (`%{"version" => _,
  "canvas" => _, "elements" => _}`). Pre-switch rows hold the legacy
  editor canvas (`%{"width" => _, "height" => _, "elements" => _,
  "background" => _}`) — `load/1` detects those by the missing
  `"version"` key and converts through `OpenFresco.OgImport`, so old
  templates keep working with no DB migration; the next editor save
  persists the scene form.
  """

  alias OpenFresco.OgImport
  alias OpenFresco.Scene
  alias OpenFresco.Substitute

  @doc """
  Returns the template's `%OpenFresco.Scene{}`, converting legacy canvas
  maps on the fly. A nil/empty/unparseable canvas yields `blank/0` —
  rendering must never crash on a malformed stored document.
  """
  @spec load(map() | nil) :: Scene.t()
  def load(%{"version" => _} = scene_map) do
    case Scene.from_map(scene_map) do
      {:ok, scene} -> scene
      # A corrupt row renders as blank rather than crashing; the decode
      # error (with JSON path) is available to surface in admin UIs later.
      {:error, _reason} -> blank()
    end
  end

  def load(%{} = canvas) when map_size(canvas) > 0 do
    OgImport.scene_from_canvas(canvas)
  rescue
    _ -> blank()
  end

  def load(_), do: blank()

  @doc "Serializes a scene for the JSONB column."
  @spec dump(Scene.t()) :: map()
  def dump(%Scene{} = scene), do: Scene.to_map(scene)

  @doc "A fresh 1200×630 scene with the house dark background."
  @spec blank() :: Scene.t()
  def blank do
    Scene.new(width: 1200, height: 630, background: Scene.solid("#0b1220"))
  end

  @doc """
  Unique `{{slot}}`s used by the scene, `[%{name: _, type: :text | :image}]`
  — same shape `PhoenixKitOG.Slots.used/1` returned for legacy canvases,
  so `Variables.resolve/3` and the assignments UI consume it unchanged.
  """
  @spec slots(Scene.t()) :: [%{name: String.t(), type: :text | :image}]
  def slots(%Scene{} = scene), do: Substitute.slots(scene)
end
