defmodule PhoenixKitOG.Render.MediaTest do
  use ExUnit.Case, async: true

  alias OpenFresco.Scene
  alias PhoenixKitOG.Render.Media

  defp scene_with_image_slot do
    Scene.new(width: 600, height: 315, background: Scene.solid("#ffffff"))
    |> Scene.add(
      Scene.image("hero", box: %{x: 0, y: 0, w: 300, h: 200}, value: Scene.placeholder("Hero"))
    )
  end

  defp scene_with_bg_slot do
    Scene.new(
      width: 600,
      height: 315,
      background: Scene.image_fill(Scene.placeholder("Bg"), :cover)
    )
  end

  describe "resolve_image_value/1" do
    test "data:/http(s) pass through" do
      assert Media.resolve_image_value("data:image/png;base64,AA==") ==
               "data:image/png;base64,AA=="

      assert Media.resolve_image_value("https://x.test/a.png") == "https://x.test/a.png"
    end

    test "file:// and host-relative are dropped" do
      assert Media.resolve_image_value("file:///etc/passwd") == nil
      assert Media.resolve_image_value("/files/signed") == nil
    end

    test "an unresolvable media UUID is dropped (no storage in unit env)" do
      assert Media.resolve_image_value("0197a5b3-0000-7000-8000-000000000000") == nil
    end
  end

  describe "prepare/3 in :preview mode" do
    test "unresolved image slots stay for OpenFresco's labeled stand-in" do
      {scene, values} = Media.prepare(scene_with_image_slot(), %{}, :preview)

      assert [%{value: %{placeholder: "Hero"}}] = scene.elements
      assert values == %{}
    end
  end

  describe "prepare/3 in :public mode" do
    test "an image ELEMENT with an unresolved slot is dropped" do
      {scene, _values} = Media.prepare(scene_with_image_slot(), %{}, :public)
      assert scene.elements == []
    end

    test "an image element with a resolved slot stays" do
      values = %{"Hero" => "data:image/png;base64,AA=="}
      {scene, out_values} = Media.prepare(scene_with_image_slot(), values, :public)

      assert [%{value: %{placeholder: "Hero"}}] = scene.elements
      assert out_values["Hero"] == "data:image/png;base64,AA=="
    end

    test "an image BACKGROUND with an unresolved slot falls back to the dark solid" do
      {scene, _} = Media.prepare(scene_with_bg_slot(), %{}, :public)
      assert %{type: :solid, color: "#0b1220"} = scene.canvas.background
    end

    test "a resolved image background stays an image fill" do
      {scene, _} =
        Media.prepare(scene_with_bg_slot(), %{"Bg" => "data:image/png;base64,AA=="}, :public)

      assert %{type: :image} = scene.canvas.background
    end
  end

  test "image-typed values that can't resolve are removed from the values map" do
    values = %{"Hero" => "file:///etc/passwd", "Title" => "keep me"}

    scene =
      scene_with_image_slot()
      |> Scene.add(Scene.text("t", value: Scene.placeholder("Title")))

    {_scene, out} = Media.prepare(scene, values, :preview)

    refute Map.has_key?(out, "Hero")
    assert out["Title"] == "keep me"
  end
end
