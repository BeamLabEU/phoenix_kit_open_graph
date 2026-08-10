defmodule PhoenixKitOG.SceneEdit do
  @moduledoc """
  Editor-side scene mutations the property panel drives — the
  counterpart to `OpenFresco.Editor.Ops` (which owns pointer gestures:
  move/resize/hit-test/front/delete). Everything here takes untrusted
  form input, so every field goes through a whitelist + coercion; an
  unknown field or junk value returns the scene unchanged.

  Also owns element insertion defaults (the Insert menu) and the
  background fill-type switch (`Scene.switch_fill/2` retains inactive
  variants in the fill map itself, so Color → Image → Gradient → Color
  round-trips losslessly — persisted with the scene).
  """

  alias OpenFresco.Editor.Ops
  alias OpenFresco.Scene

  @canvas_dim_range 1..10_000

  # =========================================================================
  # Element insertion
  # =========================================================================

  @doc """
  Builds and adds a default element for an Insert-menu kind. Returns
  `{scene, new_element_id}`.
  """
  @spec insert(Scene.t(), String.t()) :: {Scene.t(), String.t()}
  def insert(%Scene{} = scene, kind) do
    id = gen_id(kind)
    {x, y} = stagger(scene)

    element = build_element(kind, scene, id, x, y)

    {Scene.add(scene, element), id}
  end

  defp build_element("text", _scene, id, x, y) do
    Scene.text(id,
      box: %{x: x, y: y, w: 500, h: 90},
      value: "Edit this text",
      size: 48,
      weight: 700,
      fill: Scene.solid("#ffffff")
    )
  end

  defp build_element("text_var", scene, id, x, y) do
    Scene.text(id,
      box: %{x: x, y: y, w: 500, h: 90},
      value: Scene.placeholder(next_slot_name(scene, "Text")),
      size: 48,
      weight: 700,
      fill: Scene.solid("#ffffff")
    )
  end

  defp build_element("image", _scene, id, x, y),
    do: Scene.image(id, box: %{x: x, y: y, w: 320, h: 220}, value: "", fit: :cover)

  defp build_element("image_var", scene, id, x, y) do
    Scene.image(id,
      box: %{x: x, y: y, w: 320, h: 220},
      value: Scene.placeholder(next_slot_name(scene, "Image")),
      fit: :cover
    )
  end

  defp build_element("rect", _scene, id, x, y),
    do: Scene.shape(id, box: %{x: x, y: y, w: 260, h: 160}, fill: Scene.solid("#1e293b"))

  defp build_element("button", _scene, id, x, y) do
    Scene.button(id,
      box: %{x: x, y: y, w: 220, h: 56},
      label: "Read more",
      auto_width: true
    )
  end

  defp build_element("stamp", _scene, id, x, y),
    do: Scene.stamp(id, box: %{x: x, y: y, w: 260, h: 48}, value: "NEW")

  defp build_element("global:" <> global, _scene, id, x, y) do
    Scene.text(id,
      box: %{x: x, y: y, w: 500, h: 48},
      value: "[[#{global}]]",
      size: 24,
      fill: Scene.solid("#94a3b8")
    )
  end

  defp build_element(_kind, _scene, id, x, y),
    do: Scene.text(id, box: %{x: x, y: y, w: 500, h: 90}, value: "Edit this text")

  @doc "Next free `PrefixN` slot name (`Text`, `Text2`, `Text3`, …)."
  @spec next_slot_name(Scene.t(), String.t()) :: String.t()
  def next_slot_name(%Scene{} = scene, prefix) do
    taken = scene |> PhoenixKitOG.SceneStore.slots() |> MapSet.new(& &1.name)

    Enum.reduce_while(1..1_000, prefix, fn n, _ ->
      candidate = if n == 1, do: prefix, else: "#{prefix}#{n}"
      if MapSet.member?(taken, candidate), do: {:cont, candidate}, else: {:halt, candidate}
    end)
  end

  # =========================================================================
  # Element field updates (property panel)
  # =========================================================================

  @text_fields ~w(value label)
  @num_fields %{
    "size" => {8, 400},
    "weight" => {100, 900},
    "radius" => {0, 300},
    "padding" => {0, 200},
    "gap" => {0, 400},
    "line_height" => {0.8, 3.0},
    "underlay_opacity" => {0.0, 1.0}
  }
  @enum_fields %{
    "align" => ~w(left center right),
    "valign" => ~w(top middle bottom),
    "fit" => ~w(cover contain stretch),
    "preset" => ~w(solid outline soft),
    "underlay_color" => ~w(dark light),
    "anchor_edge" => ~w(below above)
  }

  @doc """
  Applies one property-panel field change to the element `id`.
  String fields pass through; `{{name}}` image/text values become
  placeholder maps; numeric/enum fields are coerced + clamped; box
  fields route through `Ops.set_box/3`. Unknown fields no-op.
  """
  @spec update_element(Scene.t(), String.t(), String.t(), term()) :: Scene.t()
  def update_element(%Scene{} = scene, id, field, value) do
    case field_kind(field) do
      :text -> put_field(scene, id, String.to_existing_atom(field), text_value(value))
      :box -> put_box_field(scene, id, field, value)
      :num -> put_num_field(scene, id, field, value)
      :enum -> put_enum_field(scene, id, field, value)
      :named -> put_named_field(scene, id, field, value)
      :anchor -> put_anchor_field(scene, id, field, value)
      :unknown -> scene
    end
  end

  # Which family a property-panel field belongs to. Split out of the `cond`
  # this used to be so each family's coercion lives in its own function —
  # the router stays flat and the branches stay individually readable.
  @anchor_fields %{"anchor_to" => :to, "anchor_edge" => :edge, "anchor_gap" => :gap}
  @named_fields ~w(color text_color font auto_width mask_edge)

  defp field_kind(field) do
    cond do
      field in @text_fields -> :text
      field in ~w(x y w h) -> :box
      Map.has_key?(@num_fields, field) -> :num
      Map.has_key?(@enum_fields, field) and field != "anchor_edge" -> :enum
      field in @named_fields -> :named
      Map.has_key?(@anchor_fields, field) -> :anchor
      true -> :unknown
    end
  end

  defp put_box_field(scene, id, field, value) do
    with %{box: box} <- find(scene, id),
         {n, _} <- Float.parse(to_string(value)) do
      Ops.set_box(scene, id, Map.put(box, String.to_existing_atom(field), n))
    else
      _ -> scene
    end
  end

  defp put_num_field(scene, id, field, value) do
    {min, max} = @num_fields[field]

    case Float.parse(to_string(value)) do
      {n, _} -> put_field(scene, id, String.to_existing_atom(field), clamp(n, min, max))
      :error -> scene
    end
  end

  defp put_enum_field(scene, id, field, value) do
    if value in @enum_fields[field] do
      put_field(scene, id, String.to_existing_atom(field), String.to_existing_atom(value))
    else
      scene
    end
  end

  defp put_named_field(scene, id, "color", value),
    do: put_field(scene, id, :fill, Scene.solid(to_string(value)))

  defp put_named_field(scene, id, "text_color", value),
    do: put_field(scene, id, :text_fill, Scene.solid(to_string(value)))

  defp put_named_field(scene, id, "font", value),
    do: put_field(scene, id, :font, to_string(value))

  defp put_named_field(scene, id, "auto_width", value),
    do: put_field(scene, id, :auto_width, value in [true, "true", "on"])

  defp put_named_field(scene, id, "mask_edge", value), do: set_mask_edge(scene, id, value)

  defp put_anchor_field(scene, id, field, value),
    do: set_anchor(scene, id, @anchor_fields[field], value)

  @doc "Moves the element behind every other element (0.2.0 stacking API)."
  @spec send_to_back(Scene.t(), String.t()) :: Scene.t()
  defdelegate send_to_back(scene, id), to: Ops

  # =========================================================================
  # Canvas / background updates
  # =========================================================================

  @doc """
  Applies a template-props field change (canvas size, background value
  fields). Background *type* switches go through `switch_background/2`.
  """
  @spec update_canvas(Scene.t(), String.t(), term()) :: Scene.t()
  def update_canvas(%Scene{} = scene, field, value), do: put_canvas_field(scene, field, value)

  defp put_canvas_field(scene, "bg_color", value),
    do: put_background(scene, Scene.solid(to_string(value)))

  defp put_canvas_field(scene, "bg_image_value", value),
    do: update_background(scene, fn bg -> %{bg | value: text_value(value)} end)

  # The Variable-mode name input sends the BARE name; wrap it into a
  # placeholder (empty name = back to constant-with-no-image).
  defp put_canvas_field(scene, "bg_image_variable_name", value),
    do: update_background(scene, fn bg -> %{bg | value: bg_variable_value(value)} end)

  defp put_canvas_field(scene, "bg_image_fit", value) when value in ~w(cover contain stretch),
    do: update_background(scene, fn bg -> %{bg | fit: String.to_existing_atom(value)} end)

  defp put_canvas_field(scene, "bg_gradient_angle", value),
    do: update_gradient(scene, fn g -> %{g | angle: dim(value, 0)} end)

  defp put_canvas_field(scene, "bg_gradient_from", value),
    do: update_gradient(scene, fn g -> put_stop_color(g, 0, value) end)

  defp put_canvas_field(scene, "bg_gradient_to", value),
    do: update_gradient(scene, fn g -> put_stop_color(g, 1, value) end)

  defp put_canvas_field(scene, _field, _value), do: scene

  defp bg_variable_value(value) do
    case String.trim(to_string(value)) do
      "" -> ""
      name -> Scene.placeholder(name)
    end
  end

  @doc """
  Switches the background fill type via `Scene.switch_fill/2` (0.2.0):
  the fill map itself retains inactive variants, so Color ↔ Image ↔
  Gradient round-trips losslessly — in the persisted scene, no
  LiveView-side stash needed.
  """
  @spec switch_background(Scene.t(), String.t()) :: Scene.t()
  def switch_background(%Scene{} = scene, type) when type in ~w(solid image gradient) do
    target = String.to_existing_atom(type)
    current = scene.canvas.background || Scene.solid("#0b1220")

    put_background(scene, Scene.switch_fill(current, target))
  end

  def switch_background(scene, _type), do: scene

  # =========================================================================
  # Internals
  # =========================================================================

  defp find(%Scene{elements: elements}, id), do: Enum.find(elements, &(&1.id == id))

  defp put_field(%Scene{} = scene, id, key, value) do
    update_in(scene.elements, fn elements ->
      Enum.map(elements, fn
        %{id: ^id} = el -> Map.put(el, key, value)
        el -> el
      end)
    end)
  end

  # `{{Name}}` becomes a placeholder map (the canonical slot form);
  # anything else stays a literal string.
  defp text_value(value) do
    v = to_string(value)

    case Regex.run(~r/\A\{\{(\w+)\}\}\z/, String.trim(v)) do
      [_, name] -> Scene.placeholder(name)
      _ -> v
    end
  end

  defp set_anchor(scene, id, key, value) do
    case find(scene, id) do
      nil -> scene
      el -> put_anchor(scene, id, el, key, value)
    end
  end

  # Clearing the target removes the anchor outright; every other key needs an
  # anchor already present, so those funnel through put_existing_anchor/5.
  defp put_anchor(scene, id, _el, :to, value) when value in [nil, ""],
    do: put_field(scene, id, :anchor, nil)

  defp put_anchor(scene, id, el, :to, value) do
    # No self-anchoring, and the target must exist. (Cycle chains are
    # OpenFresco's concern at layout time; the panel prevents the trivial
    # self-loop.)
    if value != id and find(scene, to_string(value)) do
      anchor = el[:anchor] || Scene.anchor(to_string(value), :below, gap: 16)
      put_field(scene, id, :anchor, %{anchor | to: to_string(value)})
    else
      scene
    end
  end

  defp put_anchor(scene, id, el, key, value) do
    case el[:anchor] do
      nil -> scene
      anchor -> put_existing_anchor(scene, id, anchor, key, value)
    end
  end

  defp put_existing_anchor(scene, id, anchor, :edge, value) do
    if value in @enum_fields["anchor_edge"] do
      put_field(scene, id, :anchor, %{anchor | edge: String.to_existing_atom(value)})
    else
      scene
    end
  end

  defp put_existing_anchor(scene, id, anchor, :gap, value) do
    case Float.parse(to_string(value)) do
      {n, _} -> put_field(scene, id, :anchor, %{anchor | gap: clamp(n, 0, 400)})
      :error -> scene
    end
  end

  defp put_existing_anchor(scene, _id, _anchor, _key, _value), do: scene

  # Preset gradient masks for the image "Fade edge" control — the
  # split-card effect (photo fading into the text field). Angle
  # semantics per OpenFresco: offset 0 sits at the named edge.
  @mask_angles %{"left" => 0, "right" => 180, "top" => 90, "bottom" => 270}

  @doc "Mask-edge preset names the Fade control offers."
  @spec mask_edges() :: [String.t()]
  def mask_edges, do: ["none" | Map.keys(@mask_angles) |> Enum.sort()]

  @doc """
  Reads an image element's mask back into a preset name — "none",
  one of the edges, or "custom" for a mask this module didn't build.
  """
  @spec mask_edge_of(map()) :: String.t()
  def mask_edge_of(%{mask: nil}), do: "none"

  def mask_edge_of(%{mask: %{angle: angle, stops: [%{alpha: a0} | _]}}) when a0 < 0.05 do
    Enum.find_value(@mask_angles, "custom", fn {edge, a} -> a == angle && edge end)
  end

  def mask_edge_of(%{mask: %{}}), do: "custom"
  def mask_edge_of(_), do: "none"

  defp set_mask_edge(scene, id, value) do
    case find(scene, id) do
      %{type: :image} ->
        cond do
          value == "none" ->
            put_field(scene, id, :mask, nil)

          angle = @mask_angles[value] ->
            put_field(
              scene,
              id,
              :mask,
              Scene.gradient(angle, [
                %{offset: 0.0, color: "#000000", alpha: 0.0},
                %{offset: 0.4, color: "#000000", alpha: 1.0},
                %{offset: 1.0, color: "#000000", alpha: 1.0}
              ])
            )

          true ->
            scene
        end

      _ ->
        scene
    end
  end

  defp put_background(%Scene{} = scene, fill),
    do: update_in(scene.canvas, &Map.put(&1, :background, fill))

  defp update_background(%Scene{} = scene, fun) do
    case scene.canvas.background do
      %{type: :image} = bg -> put_background(scene, fun.(bg))
      _ -> scene
    end
  end

  defp update_gradient(%Scene{} = scene, fun) do
    case scene.canvas.background do
      %{type: :gradient} = g -> put_background(scene, fun.(g))
      _ -> scene
    end
  end

  defp put_stop_color(%{stops: stops} = gradient, index, color) do
    %{gradient | stops: List.update_at(stops, index, &%{&1 | color: to_string(color)})}
  end

  defp gen_id(kind) do
    "#{kind |> String.replace(~r/[^a-z]+/, "")}-#{System.unique_integer([:positive])}"
  end

  # New elements land staggered from the top-left so consecutive
  # inserts don't stack invisibly.
  defp stagger(%Scene{} = scene) do
    n = length(scene.elements)
    {60 + rem(n, 6) * 40, 60 + rem(n, 6) * 40}
  end

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)

  defp dim(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, _} when n in @canvas_dim_range -> n
      _ -> fallback
    end
  end
end
