defmodule PhoenixKitOG.SceneStoreTest do
  use ExUnit.Case, async: true

  alias OpenFresco.Scene
  alias PhoenixKitOG.SceneStore

  @legacy_canvas %{
    "width" => 600,
    "height" => 315,
    "background" => %{"type" => "color", "value" => "#123456"},
    "elements" => [
      %{
        "type" => "text",
        "id" => "t1",
        "x" => 20,
        "y" => 30,
        "width" => 300,
        "height" => 60,
        "text" => "{{Title}}",
        "size" => 32,
        "color" => "#ffffff"
      },
      %{
        "type" => "image",
        "id" => "i1",
        "x" => 400,
        "y" => 40,
        "width" => 150,
        "height" => 150,
        "src" => "{{Hero}}"
      }
    ]
  }

  describe "load/1" do
    test "a scene map (has \"version\") loads as-is" do
      scene = SceneStore.blank()
      assert %Scene{} = loaded = SceneStore.load(SceneStore.dump(scene))
      assert loaded.canvas.width == 1200
    end

    test "a legacy editor canvas lazily migrates through OgImport" do
      assert %Scene{} = scene = SceneStore.load(@legacy_canvas)
      assert scene.canvas.width == 600
      assert scene.canvas.height == 315

      names = scene |> SceneStore.slots() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Hero", "Title"]
    end

    test "nil / empty / junk yields the blank scene, never a raise" do
      for input <- [nil, %{}, "not a map", %{"version" => "999", "canvas" => "junk"}] do
        assert %Scene{} = scene = SceneStore.load(input)
        assert scene.canvas.width == 1200
      end
    end
  end

  test "dump/load round-trips a scene" do
    scene = SceneStore.load(@legacy_canvas)
    assert SceneStore.load(SceneStore.dump(scene)) |> SceneStore.dump() == SceneStore.dump(scene)
  end

  test "slots/1 returns the legacy Slots.used/1 shape with inferred types" do
    slots = @legacy_canvas |> SceneStore.load() |> SceneStore.slots()

    assert %{name: "Title", type: :text} in slots
    assert %{name: "Hero", type: :image} in slots
  end
end
