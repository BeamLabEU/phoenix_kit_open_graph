defmodule PhoenixKitOG.Web.TemplatesLiveTest do
  @moduledoc """
  First consumer of the LiveView test plumbing, deliberately the simplest LV
  in the module: no MediaBrowser.Embed, no async preview, no optional
  publishing calls — `mount` is `load_templates/1` and a CRUD list. A boot
  failure here means the endpoint/router/hooks/sandbox wiring is wrong, not
  that some feature dependency is missing.
  """
  use PhoenixKitOG.LiveCase

  alias PhoenixKitOG.{ActivityRows, Assignments, SceneStore, Templates}

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

  describe "delete" do
    defp delete_button(view, template),
      do: element(view, ~s(button[phx-click="delete"][phx-value-uuid="#{template.uuid}"]))

    defp confirmation(view, template) do
      view
      |> delete_button(template)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-confirm")
      |> List.first()
    end

    test "the confirmation says how many assignments go with the template", %{conn: conn} do
      unused = create_template("Unused")
      once = create_template("Used Once")
      twice = create_template("Used Twice")
      {:ok, _} = Assignments.create("publishing", "default", nil, once.uuid, %{})
      {:ok, _} = Assignments.create("publishing", "group", Ecto.UUID.generate(), twice.uuid, %{})
      {:ok, _} = Assignments.create("projects", "default", nil, twice.uuid, %{})

      {:ok, view, _html} = conn |> put_test_scope(fake_scope()) |> live("/en/admin/open-graph")

      assert confirmation(view, unused) == "Delete Unused?"

      assert confirmation(view, once) ==
               "Delete Used Once? 1 assignment uses this template and will be removed with it."

      assert confirmation(view, twice) ==
               "Delete Used Twice? 2 assignments use this template and will be removed with it."
    end

    test "the delete button disables itself while the delete is in flight", %{conn: conn} do
      template = create_template("Guarded")
      {:ok, view, _html} = conn |> put_test_scope(fake_scope()) |> live("/en/admin/open-graph")

      assert has_element?(
               view,
               ~s(button[phx-click="delete"][phx-value-uuid="#{template.uuid}"][phx-disable-with="Deleting…"])
             )
    end

    test "removes the template and its assignments, each logged against the actor", %{conn: conn} do
      scope = fake_scope()
      template = create_template("Doomed")
      kept = create_template("Kept")
      {:ok, assignment} = Assignments.create("publishing", "default", nil, template.uuid, %{})

      {:ok, view, _html} = conn |> put_test_scope(scope) |> live("/en/admin/open-graph")
      html = view |> delete_button(template) |> render_click()

      assert html =~ "Deleted “Doomed”."
      refute has_element?(view, ~s(button[phx-value-uuid="#{template.uuid}"]))
      assert has_element?(view, ~s(button[phx-value-uuid="#{kept.uuid}"]))
      assert Templates.get(template.uuid) == nil
      assert Assignments.list_for_module("publishing") == []

      assert [%{actor_uuid: actor, resource_uuid: uuid}] = ActivityRows.rows("template.deleted")
      assert actor == scope.user.uuid
      assert uuid == template.uuid

      assert [%{actor_uuid: actor, resource_uuid: uuid, metadata: metadata}] =
               ActivityRows.rows("assignment.deleted")

      assert actor == scope.user.uuid
      assert uuid == assignment.uuid
      assert metadata["template_uuid"] == template.uuid
      assert metadata["scope_type"] == "default"
    end

    test "a template that is already gone reports not found", %{conn: conn} do
      template = create_template("Vanishing")
      {:ok, view, _html} = conn |> put_test_scope(fake_scope()) |> live("/en/admin/open-graph")
      {:ok, _} = Templates.delete(template)

      assert view |> delete_button(template) |> render_click() =~ "Not found."
    end
  end
end
