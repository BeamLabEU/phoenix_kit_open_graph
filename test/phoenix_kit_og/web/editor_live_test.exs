defmodule PhoenixKitOG.Web.EditorLiveTest do
  @moduledoc """
  Render-path check for the preview-platform switcher (#10).

  Source-level coverage in `editor_preview_tabs_test.exs` pins the
  `tab` payload key and the two id lists. This drives the real LiveView
  so a click actually changes the platform chrome — and so the old
  `%{"platform" => _}` payload is a silent no-op, matching the
  catch-all handler.
  """
  use PhoenixKitOG.LiveCase

  alias PhoenixKitOG.{SceneStore, Templates}

  defp create_template(name) do
    {:ok, template} =
      Templates.create(%{"name" => name, "canvas" => SceneStore.dump(SceneStore.blank())})

    template
  end

  test "clicking a platform tab wraps the stage in that platform's chrome", %{conn: conn} do
    template = create_template("Preview Tabs")

    conn = put_test_scope(conn, fake_scope())
    {:ok, view, html} = live(conn, "/en/admin/open-graph/#{template.uuid}/edit")

    assert html =~ ~s(phx-click="set_preview_platform")
    assert html =~ ~s(phx-value-tab="facebook")
    assert html =~ ~s(role="tablist")
    refute html =~ ~s(phx-value-platform)

    html = render_click(view, "set_preview_platform", %{"tab" => "facebook"})
    assert html =~ "bg-[#f0f2f5]"

    # The pre-#10 payload key. The catch-all clause swallows it, so the
    # facebook chrome must stay — a handler that still matched `platform`
    # would have switched to discord.
    html = render_click(view, "set_preview_platform", %{"platform" => "discord"})
    refute html =~ "bg-[#2b2d31]"
    assert html =~ "bg-[#f0f2f5]"
  end
end
