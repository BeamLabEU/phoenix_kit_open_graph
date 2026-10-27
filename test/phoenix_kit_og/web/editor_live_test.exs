defmodule PhoenixKitOG.Web.EditorLiveTest do
  @moduledoc """
  The template editor driven through the real LiveView: creating a
  template at `/new`, the property-panel forms, the name field, saving,
  and every `handle_info/2` clause.
  """
  use PhoenixKitOG.LiveCase

  alias OpenFresco.Scene
  alias PhoenixKitOG.{ActivityRows, SceneStore, Templates}

  @stage "og-editor-stage"

  defp create_template(name, scene \\ SceneStore.blank()) do
    {:ok, template} = Templates.create(%{"name" => name, "canvas" => SceneStore.dump(scene)})
    template
  end

  defp edit_path(template), do: "/admin/open-graph/#{template.uuid}/edit"

  defp mount_editor(conn, template, scope \\ fake_scope()) do
    {:ok, view, html} = conn |> put_test_scope(scope) |> live(edit_path(template))
    {view, html}
  end

  defp stored_scene(template),
    do: template.uuid |> Templates.get() |> Map.fetch!(:canvas) |> SceneStore.load()

  defp text_el(id, value), do: Scene.text(id, box: %{x: 40, y: 40, w: 400, h: 80}, value: value)

  defp image_el(id, opts \\ []) do
    Scene.image(
      id,
      Keyword.merge([box: %{x: 0, y: 0, w: 300, h: 200}, value: "", fit: :cover], opts)
    )
  end

  describe "the preview-platform switcher" do
    test "clicking a platform tab wraps the stage in that platform's chrome", %{conn: conn} do
      {view, html} = mount_editor(conn, create_template("Preview Tabs"))

      assert html =~ ~s(phx-click="set_preview_platform")
      assert html =~ ~s(phx-value-tab="facebook")
      assert html =~ ~s(role="tablist")
      refute html =~ ~s(phx-value-platform)

      html = render_click(view, "set_preview_platform", %{"tab" => "facebook"})
      assert html =~ "bg-[#f0f2f5]"

      # A payload without the `tab` key is swallowed by the catch-all clause,
      # so the facebook chrome must stay.
      html = render_click(view, "set_preview_platform", %{"platform" => "discord"})
      refute html =~ "bg-[#2b2d31]"
      assert html =~ "bg-[#f0f2f5]"
    end
  end

  describe "/new" do
    test "creates exactly one template and moves to its edit URL", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())

      assert {:error, {:live_redirect, %{to: to, kind: :replace}}} =
               live(conn, "/admin/open-graph/new")

      assert [template] = Templates.list()
      assert to == edit_path(template)
    end

    test "re-opening the edit URL (what a reconnect does) creates nothing", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:error, {:live_redirect, %{to: to}}} = live(conn, "/admin/open-graph/new")

      {:ok, _view, _html} = live(conn, to)
      {:ok, _view, _html} = live(conn, to)

      assert length(Templates.list()) == 1
    end

    test "takes the next free Untitled number instead of colliding", %{conn: conn} do
      create_template("Untitled 1")
      create_template("Untitled 7")
      conn = put_test_scope(conn, fake_scope())

      {:error, {:live_redirect, _}} = live(conn, "/admin/open-graph/new")

      assert "Untitled 8" in Enum.map(Templates.list(), & &1.name)
    end

    test "attributes the template.created row to the signed-in actor", %{conn: conn} do
      scope = fake_scope()

      {:error, {:live_redirect, _}} =
        conn |> put_test_scope(scope) |> live("/admin/open-graph/new")

      assert [%{actor_uuid: actor}] = ActivityRows.rows("template.created")
      assert actor == scope.user.uuid
    end

    test "an unknown template uuid goes back to the list", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())

      assert {:error, {:live_redirect, %{to: "/admin/open-graph"}}} =
               live(conn, "/admin/open-graph/#{Ecto.UUID.generate()}/edit")
    end
  end

  describe "forms" do
    # The media picker is core's component and brings its own upload form.
    defp own_forms(html) do
      html |> change_forms() |> Enum.reject(&(&1.id =~ "media-selector-modal"))
    end

    # Every state of the right-hand panel that renders a different set of
    # forms, each reached the way an author reaches it.
    defp panel_states(view) do
      insert = fn kind -> render_click(view, "insert", %{"kind" => kind}) end

      canvas = fn field, value ->
        render_change(view, "update_canvas", %{"field" => field, "value" => value})
      end

      inserted = Enum.map(~w(text text_var image image_var rect button stamp), insert)

      scene = :sys.get_state(view.pid).socket.assigns.scene
      [first, second | _] = Enum.map(scene.elements, & &1.id)
      button = Enum.find(scene.elements, &(&1.type == :button)).id

      render_click(view, "select", %{"id" => second})

      anchored =
        render_change(view, "update_prop", %{
          "el_id" => second,
          "field" => "anchor_to",
          "value" => first
        })

      render_click(view, "select", %{"id" => button})

      button_variable =
        render_change(view, "update_prop", %{
          "el_id" => button,
          "field" => "label",
          "value" => "{{cta}}"
        })

      render_click(view, "deselect")

      backgrounds = [
        render(view),
        canvas.("bg_type", "image"),
        canvas.("bg_image_variable_name", "BackgroundImage"),
        canvas.("bg_type", "gradient")
      ]

      inserted ++ [anchored, button_variable] ++ backgrounds
    end

    test "every form with phx-change also carries a phx-submit for the same event", %{conn: conn} do
      masked =
        image_el("masked",
          mask: Scene.gradient(33, [%{offset: 0.0, color: "#000000", alpha: 0.0}])
        )

      template = create_template("Forms", Scene.add(SceneStore.blank(), masked))
      {view, html} = mount_editor(conn, template)

      custom_mask = render_click(view, "select", %{"id" => "masked"})
      forms = Enum.flat_map([html, custom_mask | panel_states(view)], &own_forms/1)

      for form <- forms do
        assert form.submit == form.change, "form ##{form.id} has no phx-submit for #{form.change}"
      end

      # The states above reach every form the editor can render.
      kinds =
        forms
        |> Enum.map(&String.replace(&1.id, ~r/-form.*\z/, ""))
        |> Enum.uniq()
        |> Enum.sort()

      assert kinds ==
               Enum.sort(~w(
                 og-editor-name og-canvas-bg-type og-canvas-bg-fit og-gradient-dir
                 og-image-value og-anchor-x og-anchor-y og-text-variable og-text-value
                 og-text-align og-image-fit og-image-radius og-image-mask
                 og-button-variable og-button-label og-button-preset og-button-radius
                 og-underlay og-prop-number og-prop-color og-canvas-color
               ))
    end

    test "submitting a form that already holds its value changes nothing", %{conn: conn} do
      scene =
        SceneStore.blank()
        |> Scene.add(text_el("title", "Hello"))
        |> Scene.add(image_el("pic"))

      template = create_template("Submit Noop", scene)
      before = Templates.get(template.uuid)
      {view, _html} = mount_editor(conn, template)

      for id <- [nil, "title", "pic"] do
        html = if id, do: render_click(view, "select", %{"id" => id}), else: render(view)

        for form <- own_forms(html) do
          view |> element(~s(form[id="#{form.id}"])) |> render_submit()
          unless has_element?(view, "header .badge", "Saved"), do: flunk("dirty after #{form.id}")
        end

        render_click(view, "deselect")
      end

      assert has_element?(view, "header .badge", "Saved")
      assert ActivityRows.rows("template.updated") == []
      assert Templates.get(template.uuid).canvas == before.canvas
    end

    test "submitting a changed value commits it like a change does", %{conn: conn} do
      template =
        create_template("Submit Commit", Scene.add(SceneStore.blank(), text_el("title", "Hello")))

      {view, _html} = mount_editor(conn, template)
      render_click(view, "select", %{"id" => "title"})

      view
      |> form(~s(form[id="og-prop-number-form-title-x"]), %{"value" => "55"})
      |> render_submit()

      assert has_element?(view, "header .badge", "Unsaved…")
      render_click(view, "save_now")

      assert [%{id: "title", box: %{x: x}}] = stored_scene(template).elements
      assert x == 55
    end

    test "the custom-mask Remove button submits through LiveView and clears the mask", %{
      conn: conn
    } do
      masked =
        image_el("masked",
          mask: Scene.gradient(33, [%{offset: 0.0, color: "#000000", alpha: 0.0}])
        )

      template = create_template("Mask", Scene.add(SceneStore.blank(), masked))
      {view, _html} = mount_editor(conn, template)
      render_click(view, "select", %{"id" => "masked"})

      view
      |> form(~s(form[id="og-image-radius-form-masked"]))
      |> render_submit(%{"value" => "none"})

      render_click(view, "save_now")
      assert [%{id: "masked", mask: nil}] = stored_scene(template).elements
    end
  end

  describe "the template name" do
    test "commits on blur or Enter, not per keystroke", %{conn: conn} do
      {view, _html} = mount_editor(conn, create_template("Named"))

      assert has_element?(view, ~s(#og-editor-name-form[phx-submit="update_template_name"]))
      assert has_element?(view, ~s(#og-editor-name-form input[name="name"][phx-debounce="blur"]))
    end

    test "a commit that changes the name renames once, attributed to the actor", %{conn: conn} do
      scope = fake_scope()
      template = create_template("Before")
      {view, _html} = mount_editor(conn, template, scope)

      view |> form("#og-editor-name-form", %{"name" => "After"}) |> render_submit()

      assert Templates.get(template.uuid).name == "After"
      assert [%{actor_uuid: actor, resource_uuid: uuid}] = ActivityRows.rows("template.updated")
      assert actor == scope.user.uuid
      assert uuid == template.uuid
    end

    test "a commit that leaves the name as it was writes nothing", %{conn: conn} do
      template = create_template("Same")
      {view, _html} = mount_editor(conn, template)

      view |> form("#og-editor-name-form", %{"name" => "Same"}) |> render_submit()
      view |> form("#og-editor-name-form", %{"name" => "Same"}) |> render_change()
      view |> form("#og-editor-name-form", %{"name" => "  Same  "}) |> render_change()

      assert ActivityRows.rows("template.updated") == []
    end

    test "a name another template has is refused with a flash", %{conn: conn} do
      create_template("Taken")
      template = create_template("Mine")
      {view, _html} = mount_editor(conn, template)

      html = view |> form("#og-editor-name-form", %{"name" => "Taken"}) |> render_submit()

      assert html =~ "Could not rename template."
      assert Templates.get(template.uuid).name == "Mine"
    end
  end

  describe "variable names" do
    test "a name with a space stays a variable instead of flipping to constant text", %{
      conn: conn
    } do
      template =
        create_template(
          "Var",
          Scene.add(SceneStore.blank(), text_el("title", Scene.placeholder("Text")))
        )

      {view, _html} = mount_editor(conn, template)
      render_click(view, "select", %{"id" => "title"})

      html =
        view
        |> form(~s(form[id="og-text-variable-form-title"]), %{"value" => "My Title"})
        |> render_change()

      assert html =~ ~s(id="og-text-variable-form-title")
      refute html =~ ~s(id="og-text-value-form-title")

      render_click(view, "save_now")
      assert [%{value: %{placeholder: "My_Title"}}] = stored_scene(template).elements
    end
  end

  describe "the insert menu" do
    test "lists each site global with its label and description", %{conn: conn} do
      {_view, html} = mount_editor(conn, create_template("Menu"))

      assert html =~ "[[page_url]]"
      assert html =~ "Current page URL"
      assert html =~ "Full URL of the page carrying this OG image"
      assert html =~ "From the project_title setting"
    end
  end

  describe "saving" do
    test "the Save button disables itself while the save is in flight", %{conn: conn} do
      {view, _html} = mount_editor(conn, create_template("Buttons"))

      assert has_element?(view, ~s(button[phx-click="save_now"][phx-disable-with="Saving…"]))
    end

    test "save_now persists the scene and logs it against the actor", %{conn: conn} do
      scope = fake_scope()
      template = create_template("Save Me")
      {view, _html} = mount_editor(conn, template, scope)

      render_click(view, "insert", %{"kind" => "rect"})
      assert has_element?(view, "header .badge", "Unsaved…")

      render_click(view, "save_now")

      assert has_element?(view, "header .badge", "Saved")
      assert [%{type: :shape}] = stored_scene(template).elements

      assert [%{actor_uuid: actor, resource_uuid: uuid, metadata: %{"elements" => 1}}] =
               ActivityRows.rows("template.updated")

      assert actor == scope.user.uuid
      assert uuid == template.uuid
    end
  end

  describe "handle_info/2" do
    test ":autosave flushes a pending edit", %{conn: conn} do
      template = create_template("Autosave")
      {view, _html} = mount_editor(conn, template)
      render_click(view, "insert", %{"kind" => "stamp"})

      send(view.pid, :autosave)

      assert has_element?(view, "header .badge", "Saved")
      assert [%{type: :stamp}] = stored_scene(template).elements
    end

    test "a scene_changed from the stage is adopted and marked unsaved", %{conn: conn} do
      template = create_template("Stage Edit")
      {view, _html} = mount_editor(conn, template)
      scene = Scene.add(SceneStore.blank(), text_el("t", Scene.placeholder("FromStage")))

      send(view.pid, {:open_fresco_editor, @stage, {:scene_changed, scene}})

      assert has_element?(view, "aside li.badge", "FromStage")
      assert has_element?(view, "header .badge", "Unsaved…")

      render_click(view, "save_now")
      assert [%{id: "t"}] = stored_scene(template).elements
    end

    test "a selected id from the stage opens that element's properties", %{conn: conn} do
      template = create_template("Select", Scene.add(SceneStore.blank(), text_el("title", "Hi")))
      {view, html} = mount_editor(conn, template)
      refute html =~ "og-prop-number-form-title-x"

      send(view.pid, {:open_fresco_editor, @stage, {:selected, "title"}})

      assert has_element?(view, ~s(form[id="og-prop-number-form-title-x"]))
    end

    test "a multi-selection follows the last id and deletes as a set", %{conn: conn} do
      scene =
        SceneStore.blank()
        |> Scene.add(text_el("a", "A"))
        |> Scene.add(text_el("b", "B"))
        |> Scene.add(text_el("c", "C"))

      template = create_template("Multi", scene)
      {view, _html} = mount_editor(conn, template)

      send(view.pid, {:open_fresco_editor, @stage, {:selected_ids, ["a", "b"]}})

      assert has_element?(view, ~s(form[id="og-prop-number-form-b-x"]))
      refute has_element?(view, ~s(form[id="og-prop-number-form-a-x"]))

      render_click(view, "delete_selected")
      render_click(view, "save_now")

      assert [%{id: "c"}] = stored_scene(template).elements
    end

    test "a picked media file lands on the background it was opened for", %{conn: conn} do
      template = create_template("Bg Pick")
      {view, _html} = mount_editor(conn, template)
      render_change(view, "update_canvas", %{"field" => "bg_type", "value" => "image"})
      render_click(view, "open_media_picker", %{"target" => "background_value"})
      uuid = Ecto.UUID.generate()

      send(view.pid, {:media_selected, [uuid]})
      render_click(view, "save_now")

      assert stored_scene(template).canvas.background.value == uuid
    end

    test "a picked media file lands on the selected image element", %{conn: conn} do
      template = create_template("El Pick", Scene.add(SceneStore.blank(), image_el("pic")))
      {view, _html} = mount_editor(conn, template)
      render_click(view, "select", %{"id" => "pic"})
      render_click(view, "open_media_picker", %{"target" => "element_src"})
      uuid = Ecto.UUID.generate()

      send(view.pid, {:media_selected, [uuid]})
      render_click(view, "save_now")

      assert [%{id: "pic", value: ^uuid}] = stored_scene(template).elements
    end

    test "an empty selection, or one with no element to receive it, changes nothing", %{
      conn: conn
    } do
      template = create_template("No Pick", Scene.add(SceneStore.blank(), image_el("pic")))
      {view, _html} = mount_editor(conn, template)

      render_click(view, "open_media_picker", %{"target" => "element_src"})
      send(view.pid, {:media_selected, []})
      assert has_element?(view, "header .badge", "Saved")

      # element_src with nothing selected
      render_click(view, "open_media_picker", %{"target" => "element_src"})
      send(view.pid, {:media_selected, [Ecto.UUID.generate()]})
      assert has_element?(view, "header .badge", "Saved")
    end

    test "closing the picker forgets its target", %{conn: conn} do
      template = create_template("Close Pick")
      {view, _html} = mount_editor(conn, template)
      render_change(view, "update_canvas", %{"field" => "bg_type", "value" => "image"})
      render_click(view, "save_now")
      render_click(view, "open_media_picker", %{"target" => "background_value"})

      send(view.pid, {:media_selector_closed})
      # With the target gone, a late selection has nowhere to land.
      send(view.pid, {:media_selected, [Ecto.UUID.generate()]})

      assert has_element?(view, "header .badge", "Saved")
    end

    test "an unexpected message is ignored and the editor keeps working", %{conn: conn} do
      template = create_template("Stray")
      {view, _html} = mount_editor(conn, template)

      send(view.pid, {:something, :unexpected})
      send(view.pid, {:open_fresco_editor, "another-stage", {:selected, "x"}})

      render_click(view, "insert", %{"kind" => "rect"})
      assert has_element?(view, "header .badge", "Unsaved…")
    end
  end
end
