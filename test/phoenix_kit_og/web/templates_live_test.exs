defmodule PhoenixKitOG.Web.TemplatesLiveTest do
  @moduledoc """
  First consumer of the LiveView test plumbing, deliberately the simplest LV
  in the module: no MediaBrowser.Embed, no async preview, no optional
  publishing calls — `mount` is `load_templates/1` and a CRUD list. A boot
  failure here means the endpoint/router/hooks/sandbox wiring is wrong, not
  that some feature dependency is missing.
  """
  use PhoenixKitOG.LiveCase

  alias PhoenixKitOG.{SceneStore, Templates}

  defp create_template(name) do
    {:ok, template} =
      Templates.create(%{"name" => name, "canvas" => SceneStore.dump(SceneStore.blank())})

    template
  end

  test "mounts and renders the template list", %{conn: conn} do
    template = create_template("Render Probe")

    conn = put_test_scope(conn, fake_scope())
    {:ok, _view, html} = live(conn, "/en/admin/open-graph")

    assert html =~ "OpenGraph templates"
    assert html =~ template.name
  end

  test "renders the empty state without a template", %{conn: conn} do
    conn = put_test_scope(conn, fake_scope())
    {:ok, _view, html} = live(conn, "/en/admin/open-graph")

    assert html =~ "OpenGraph templates"
  end
end
