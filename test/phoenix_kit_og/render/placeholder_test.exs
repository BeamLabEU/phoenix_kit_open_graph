defmodule PhoenixKitOG.Render.PlaceholderTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Render.Placeholder

  test "data_url/0 is a base64 SVG data URL" do
    url = Placeholder.data_url()
    assert String.starts_with?(url, "data:image/svg+xml;base64,")

    "data:image/svg+xml;base64," <> b64 = url
    assert {:ok, decoded} = Base.decode64(b64)
    assert String.contains?(decoded, "<svg")
    assert String.contains?(decoded, "Placeholder image")
  end

  test "svg/0 returns the raw SVG source" do
    svg = Placeholder.svg()
    assert String.contains?(svg, "viewBox=\"0 0 400 400\"")
  end

  describe "inline_svg/4" do
    test "draws the full artwork fitted to the rect as native shapes" do
      out = Placeholder.inline_svg(100, 40, 235, 235) |> IO.iodata_to_binary()

      # Frame fills the exact bounds.
      assert out =~ ~s|<rect x="100" y="40" width="235" height="235"|
      # Arrows + tips + center dot + caption all present.
      assert out =~ "<line "
      assert out =~ "<polygon "
      assert out =~ "<circle "
      assert out =~ "Placeholder image"
      # Caption is a top-level <text> with the server-safe font chain,
      # NOT a nested SVG image (which rasterizers font-starve or drop).
      assert out =~ ~s|font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif"|
      refute out =~ "<image"
      refute out =~ "data:image/svg+xml"
    end

    test "motif scales with the smaller dimension on a wide rect" do
      out = Placeholder.inline_svg(0, 0, 1200, 630) |> IO.iodata_to_binary()

      # min(1200, 630) = 630 → center dot r = 0.025 * 630 = 15.75.
      assert out =~ ~s|<circle cx="600" cy="315" r="15.75"|
    end

    test "returns nothing for a rect with no visible area" do
      assert Placeholder.inline_svg(10, 10, 0, 50) == []
      assert Placeholder.inline_svg(10, 10, 50, 0) == []
      assert Placeholder.inline_svg(10, 10, -5, 50) == []
    end

    test "output is deterministic" do
      a = Placeholder.inline_svg(3.5, 7.25, 120.0, 88) |> IO.iodata_to_binary()
      b = Placeholder.inline_svg(3.5, 7.25, 120.0, 88) |> IO.iodata_to_binary()
      assert a == b
    end
  end
end
