defmodule PhoenixKitOG.Web.StagePlaceholderTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Web.StagePlaceholder

  test "data_url/0 is a decodable base64 SVG with the arrows artwork" do
    url = StagePlaceholder.data_url()
    assert "data:image/svg+xml;base64," <> b64 = url
    assert {:ok, svg} = Base.decode64(b64)
    assert svg =~ "<polygon"
    assert svg =~ "Placeholder image"
  end
end
