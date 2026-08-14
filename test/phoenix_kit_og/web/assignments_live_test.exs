defmodule PhoenixKitOG.Web.AssignmentsLiveTest do
  @moduledoc """
  Render-path regression for issue #7 (`KeyError :preview_loading`), driven
  through the real LiveView rather than by parsing source.

  Mounting alone is NOT the regression: the initial `blank_edit_state()` has
  `template_uuid: nil`, so `edit_modal/1`'s `:if={@selected_template}` branch —
  where the crash lived — never renders and a mount-only test is green on the
  unfixed source. The bug is only reachable by picking a template, and
  `open_new` auto-picks the first one when templates exist. So the regression
  is: seed a template → mount → click "open_new" → the modal (preview panel
  included) must render.

  The source-level guard in `edit_modal_assigns_test.exs` stays alongside this:
  it catches an undeclared read in ANY branch of that component, while this
  proves the real render path end to end.
  """
  use PhoenixKitOG.LiveCase

  alias PhoenixKitOG.{SceneStore, Templates}

  defp create_template(name) do
    {:ok, template} =
      Templates.create(%{"name" => name, "canvas" => SceneStore.dump(SceneStore.blank())})

    template
  end

  test "mounts with no assignments and no templates", %{conn: conn} do
    conn = put_test_scope(conn, fake_scope())
    {:ok, _view, html} = live(conn, "/en/admin/open-graph/assignments")

    assert html =~ "og-assign-modal"
  end

  test "opening a new assignment with a template present renders the modal (issue #7)",
       %{conn: conn} do
    template = create_template("Issue 7 Probe")

    conn = put_test_scope(conn, fake_scope())
    {:ok, view, _html} = live(conn, "/en/admin/open-graph/assignments")

    # `open_new` auto-picks the first template, which makes `edit_modal/1`
    # render its `:if={@selected_template}` branch — the exact evaluation that
    # raised `KeyError :preview_loading` before the fix.
    html = render_click(view, "open_new")

    assert html =~ "modal-open"
    assert html =~ template.name
  end

  test "picking a template explicitly re-renders the modal, not a crash", %{conn: conn} do
    template = create_template("Picked Probe")

    conn = put_test_scope(conn, fake_scope())
    {:ok, view, _html} = live(conn, "/en/admin/open-graph/assignments")

    render_click(view, "open_new")

    # The reported reproduction was "picking a template" in the open modal —
    # exercise the change event the template <select> actually drives, not
    # only the auto-pick.
    html = render_change(view, "edit_change_template", %{"template_uuid" => template.uuid})

    assert html =~ "modal-open"
  end
end
