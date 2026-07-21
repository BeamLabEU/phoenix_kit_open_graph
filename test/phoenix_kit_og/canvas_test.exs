defmodule PhoenixKitOG.CanvasTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Canvas

  describe "elements/1" do
    test "returns the elements list from a canvas map" do
      canvas = %{"elements" => [%{"type" => "text"}, %{"type" => "rect"}]}
      assert Canvas.elements(canvas) == [%{"type" => "text"}, %{"type" => "rect"}]
    end

    test "returns [] when no elements key" do
      assert Canvas.elements(%{}) == []
    end
  end

  describe "default_element/2" do
    test "text elements carry an id, type, and default typography" do
      el = Canvas.default_element("text", [])
      assert el["type"] == "text"
      assert is_binary(el["id"])
      assert Map.has_key?(el, "text")
      assert Map.has_key?(el, "font")
      assert Map.has_key?(el, "size")
    end

    test "text_var elements seed a {{name}} into the text field" do
      el = Canvas.default_element("text_var", [])
      assert el["type"] == "text"
      # The default variable name is auto-generated; the text should
      # wrap it in the {{...}} slot syntax.
      assert String.match?(el["text"], ~r/^\{\{\w+\}\}$/)
    end

    test "image elements carry width/height/fit defaults" do
      el = Canvas.default_element("image", [])
      assert el["type"] == "image"
      assert is_binary(el["id"])
      assert el["fit"] in ["fill", "contain", "stretch"]
    end

    test "rect elements carry fill/stroke defaults" do
      el = Canvas.default_element("rect", [])
      assert el["type"] == "rect"
      assert is_binary(el["fill"])
    end
  end

  describe "update_canvas_field/3 — background_type round-trip" do
    test "switching color -> image -> color restores the stashed color" do
      canvas = %{"background" => %{"type" => "color", "value" => "#ff6600"}}

      as_image = Canvas.update_canvas_field(canvas, "background_type", "image")
      assert get_in(as_image, ["background", "type"]) == "image"
      # Fresh image side starts empty — the hex color must not leak in.
      assert get_in(as_image, ["background", "value"]) == ""

      back = Canvas.update_canvas_field(as_image, "background_type", "color")
      assert get_in(back, ["background", "type"]) == "color"
      assert get_in(back, ["background", "value"]) == "#ff6600"
    end

    test "switching image -> color -> image restores the stashed image source" do
      canvas = %{"background" => %{"type" => "image", "value" => "{{BackgroundImage}}"}}

      as_color = Canvas.update_canvas_field(canvas, "background_type", "color")
      assert get_in(as_color, ["background", "value"]) == "#0b1220"

      back = Canvas.update_canvas_field(as_color, "background_type", "image")
      assert get_in(back, ["background", "value"]) == "{{BackgroundImage}}"
    end

    test "re-selecting the current type is a no-op on the value" do
      canvas = %{"background" => %{"type" => "color", "value" => "#ff6600"}}
      same = Canvas.update_canvas_field(canvas, "background_type", "color")
      assert get_in(same, ["background", "value"]) == "#ff6600"
    end
  end
end
