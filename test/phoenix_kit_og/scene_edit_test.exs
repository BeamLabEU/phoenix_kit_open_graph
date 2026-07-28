defmodule PhoenixKitOG.SceneEditTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.{SceneEdit, SceneStore}

  defp find(scene, id), do: Enum.find(scene.elements, &(&1.id == id))

  describe "insert/2" do
    test "every insert kind adds one element" do
      kinds = ~w(text text_var image image_var rect button stamp global:site_url)

      scene =
        Enum.reduce(kinds, SceneStore.blank(), fn kind, scene ->
          {scene, _id} = SceneEdit.insert(scene, kind)
          scene
        end)

      assert length(scene.elements) == length(kinds)
    end

    test "variable kinds seed distinct slot names" do
      {scene, _} = SceneEdit.insert(SceneStore.blank(), "text_var")
      {scene, _} = SceneEdit.insert(scene, "text_var")

      names = scene |> SceneStore.slots() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Text", "Text2"]
    end
  end

  describe "update_element/4" do
    setup do
      {scene, id} = SceneEdit.insert(SceneStore.blank(), "text")
      %{scene: scene, id: id}
    end

    test "coerces + clamps numeric fields", %{scene: scene, id: id} do
      scene = SceneEdit.update_element(scene, id, "size", "999")
      assert find(scene, id).size == 400

      scene = SceneEdit.update_element(scene, id, "size", "junk")
      assert find(scene, id).size == 400
    end

    test "whitelists enum fields", %{scene: scene, id: id} do
      scene = SceneEdit.update_element(scene, id, "align", "center")
      assert find(scene, id).align == :center

      scene = SceneEdit.update_element(scene, id, "align", "diagonal")
      assert find(scene, id).align == :center
    end

    test "color becomes a solid fill", %{scene: scene, id: id} do
      scene = SceneEdit.update_element(scene, id, "color", "#ff0000")
      assert find(scene, id).fill == %{type: :solid, color: "#ff0000"}
    end

    test "a {{Name}} value becomes a placeholder map", %{scene: scene, id: id} do
      scene = SceneEdit.update_element(scene, id, "value", "{{Title}}")
      assert find(scene, id).value == %{placeholder: "Title"}

      scene = SceneEdit.update_element(scene, id, "value", "plain words")
      assert find(scene, id).value == "plain words"
    end

    test "unknown fields no-op", %{scene: scene, id: id} do
      assert SceneEdit.update_element(scene, id, "__proto__", "x") == scene
    end
  end

  describe "anchors" do
    test "anchor_to wires and unwires; self-anchor is rejected" do
      {scene, a} = SceneEdit.insert(SceneStore.blank(), "text")
      {scene, b} = SceneEdit.insert(scene, "button")

      scene = SceneEdit.update_element(scene, b, "anchor_to", a)
      assert %{to: ^a, edge: :below} = find(scene, b).anchor

      scene = SceneEdit.update_element(scene, b, "anchor_edge", "above")
      assert find(scene, b).anchor.edge == :above

      scene = SceneEdit.update_element(scene, b, "anchor_gap", "48")
      assert find(scene, b).anchor.gap == 48.0

      # Self-anchoring is a trivial cycle — rejected.
      assert SceneEdit.update_element(scene, b, "anchor_to", b) == scene

      scene = SceneEdit.update_element(scene, b, "anchor_to", "")
      assert find(scene, b).anchor == nil
    end
  end

  describe "background type switch (Scene.switch_fill)" do
    test "solid -> image -> gradient -> solid round-trips losslessly" do
      scene = SceneStore.blank()
      scene = SceneEdit.update_canvas(scene, "bg_color", "#ff6600")

      scene = SceneEdit.switch_background(scene, "image")
      assert scene.canvas.background.type == :image

      scene = SceneEdit.switch_background(scene, "gradient")
      assert scene.canvas.background.type == :gradient

      scene = SceneEdit.switch_background(scene, "solid")
      # 0.2.0 retains inactive variants inside the fill map itself.
      assert scene.canvas.background.type == :solid
      assert scene.canvas.background.color == "#ff6600"
    end

    test "re-selecting the current type keeps the fill" do
      scene = SceneStore.blank()
      same = SceneEdit.switch_background(scene, "solid")
      assert same.canvas.background.type == :solid
    end
  end

  describe "update_canvas/3" do
    test "canvas size is pinned - width/height fields are ignored" do
      scene = SceneEdit.update_canvas(SceneStore.blank(), "width", "800")
      assert scene.canvas.width == 1200

      scene = SceneEdit.update_canvas(scene, "height", "99999999")
      assert scene.canvas.height == 630
    end

    test "gradient stops + angle edit in place" do
      scene = SceneEdit.switch_background(SceneStore.blank(), "gradient")

      scene = SceneEdit.update_canvas(scene, "bg_gradient_from", "#111111")
      scene = SceneEdit.update_canvas(scene, "bg_gradient_to", "#222222")
      scene = SceneEdit.update_canvas(scene, "bg_gradient_angle", "90")

      assert %{
               type: :gradient,
               angle: 90,
               stops: [%{color: "#111111"}, %{color: "#222222"}]
             } = scene.canvas.background
    end

    test "bg variable name wraps into a placeholder" do
      scene = SceneEdit.switch_background(SceneStore.blank(), "image")
      scene = SceneEdit.update_canvas(scene, "bg_image_variable_name", "BackgroundImage")
      assert scene.canvas.background.value == %{placeholder: "BackgroundImage"}
    end
  end

  test "send_to_back/2 drops the element under everything" do
    {scene, a} = SceneEdit.insert(SceneStore.blank(), "rect")
    {scene, b} = SceneEdit.insert(scene, "rect")

    scene = SceneEdit.send_to_back(scene, b)
    assert find(scene, b).z < find(scene, a).z
  end
end
