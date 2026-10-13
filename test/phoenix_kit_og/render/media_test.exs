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

  describe "a shape's image fill" do
    defp scene_with_shape_fill(value) do
      Scene.new(width: 600, height: 315, background: Scene.solid("#ffffff"))
      |> Scene.add(
        Scene.shape("photo-shape",
          box: %{x: 0, y: 0, w: 300, h: 200},
          fill: Scene.image_fill(value, :cover)
        )
      )
    end

    test "unresolved is dropped in :public and kept for the stand-in in :preview" do
      scene = scene_with_shape_fill(Scene.placeholder("Hero"))

      {public, _} = Media.prepare(scene, %{}, :public)
      assert public.elements == []

      {preview, _} = Media.prepare(scene, %{}, :preview)
      assert [%{type: :shape}] = preview.elements
    end

    test "a remote URL is dropped in :public" do
      scene = scene_with_shape_fill(Scene.placeholder("Hero"))
      {public, _} = Media.prepare(scene, %{"Hero" => "https://cdn.example/x.png"}, :public)
      assert public.elements == []
    end

    test "a static remote URL or unresolvable media UUID is dropped in :public" do
      for value <- ["https://cdn.example/x.png", Ecto.UUID.generate()] do
        {public, _} = Media.prepare(scene_with_shape_fill(value), %{}, :public)
        assert public.elements == []
      end
    end

    test "a resolved data: URL keeps the shape in :public" do
      scene = scene_with_shape_fill(Scene.placeholder("Hero"))
      values = %{"Hero" => "data:image/png;base64,AA=="}

      {public, _} = Media.prepare(scene, values, :public)
      assert [%{type: :shape, fill: %{type: :image}}] = public.elements
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

  describe "remote http(s) image values" do
    defp scene_with_static_image(value) do
      Scene.new(width: 600, height: 315, background: Scene.solid("#ffffff"))
      |> Scene.add(Scene.image("logo", box: %{x: 0, y: 0, w: 300, h: 200}, value: value))
    end

    for url <- ["https://cdn.example/x.png", "http://cdn.example/x.png"] do
      test "#{url} in a slot drops the element from the :public scene" do
        {scene, _values} =
          Media.prepare(scene_with_image_slot(), %{"Hero" => unquote(url)}, :public)

        assert scene.elements == []
      end

      test "#{url} as a static element value drops the element from the :public scene" do
        {scene, _values} = Media.prepare(scene_with_static_image(unquote(url)), %{}, :public)
        assert scene.elements == []
      end

      test "#{url} as the background slot falls back to the solid in :public" do
        {scene, _values} = Media.prepare(scene_with_bg_slot(), %{"Bg" => unquote(url)}, :public)
        assert %{type: :solid} = scene.canvas.background
      end

      test "#{url} keeps its element in :preview, where the stand-in is the affordance" do
        {scene, values} =
          Media.prepare(scene_with_image_slot(), %{"Hero" => unquote(url)}, :preview)

        assert [%{id: "hero"}] = scene.elements
        assert values["Hero"] == unquote(url)
      end
    end

    test "a data: URL in the same slot keeps the element in :public" do
      {scene, _values} =
        Media.prepare(scene_with_image_slot(), %{"Hero" => "data:image/png;base64,AA=="}, :public)

      assert [%{id: "hero"}] = scene.elements
    end
  end

  describe "remote_url?/1" do
    test "is true for http and https only" do
      assert Media.remote_url?("https://x.test/a.png")
      assert Media.remote_url?("http://x.test/a.png")
      refute Media.remote_url?("data:image/png;base64,AA==")
      refute Media.remote_url?("0197a5b3-0000-7000-8000-000000000000")
      refute Media.remote_url?("")
      refute Media.remote_url?(nil)
    end
  end

  describe "preview_url/1" do
    test "returns browser-loadable references as they are" do
      assert Media.preview_url("https://x.test/a.png") == "https://x.test/a.png"
      assert Media.preview_url("/files/a.png") == "/files/a.png"
      assert Media.preview_url("data:image/png;base64,AA==") == "data:image/png;base64,AA=="
    end

    test "has nothing to show for an empty or non-binary value" do
      assert Media.preview_url(nil) == nil
      assert Media.preview_url("") == nil
      assert Media.preview_url(%{placeholder: "Hero"}) == nil
    end

    test "an unresolvable media uuid is nil, not a raise" do
      assert Media.preview_url("0197a5b3-0000-7000-8000-000000000000") == nil
    end
  end
end
