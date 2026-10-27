defmodule PhoenixKitOG.Web.AssignmentsLiveTest do
  @moduledoc """
  The assignments admin driven through the real LiveView: the modal for
  new and existing assignments, saving, removing, the custom image value,
  and every `handle_info/2` clause.

  The modal's `:if={@selected_template}` branch only renders once a
  template is picked — `open_new` auto-picks the first one — so a
  mount-only test never reaches the slot wiring or the preview panel.
  """
  use PhoenixKitOG.LiveCase

  alias OpenFresco.Scene
  alias PhoenixKitOG.{ActivityRows, Assignments, SceneStore, Templates}
  alias PhoenixKitOG.Test.Publishing

  @path "/admin/open-graph/assignments"
  @group_a "0197a5b3-aaaa-7000-8000-00000000000a"
  @group_b "0197a5b3-bbbb-7000-8000-00000000000b"

  setup do
    Publishing.put_groups([
      %{"uuid" => @group_a, "slug" => "alpha", "name" => "Alpha"},
      %{"uuid" => @group_b, "slug" => "beta", "name" => "Beta"}
    ])

    on_exit(&Publishing.reset/0)
    :ok
  end

  defp create_template(name, scene \\ SceneStore.blank()) do
    {:ok, template} = Templates.create(%{"name" => name, "canvas" => SceneStore.dump(scene)})
    template
  end

  # A text slot and an image slot.
  defp slotted_scene do
    SceneStore.blank()
    |> Scene.add(
      Scene.text("t", box: %{x: 40, y: 40, w: 400, h: 80}, value: Scene.placeholder("Title"))
    )
    |> Scene.add(
      Scene.image("i",
        box: %{x: 0, y: 200, w: 300, h: 200},
        value: Scene.placeholder("Hero"),
        fit: :cover
      )
    )
  end

  defp mount_page(conn, scope \\ fake_scope()) do
    {:ok, view, _html} = conn |> put_test_scope(scope) |> live(@path)
    view
  end

  defp assignment(scope_type, scope_uuid),
    do: Assignments.get("publishing", scope_type, scope_uuid)

  defp pick_group(view, uuid) do
    view |> form("#og-assign-scope-form", %{"scope" => "group"}) |> render_change()
    view |> form("#og-assign-group-form", %{"group_uuid" => uuid}) |> render_change()
  end

  test "mounts with no assignments and no templates", %{conn: conn} do
    view = mount_page(conn)

    assert has_element?(view, "#og-assign-modal")
    refute has_element?(view, "#og-assign-modal.modal-open")
  end

  describe "the modal" do
    test "opening a new assignment renders the template's wiring and preview", %{conn: conn} do
      template = create_template("Probe", slotted_scene())
      view = mount_page(conn)

      html = render_click(view, "open_new")

      assert html =~ "modal-open"
      assert html =~ template.name
      assert has_element?(view, ~s(form[id="og-wire-slot-form-Title"]))
      assert has_element?(view, "#og-preview-group-form")
    end

    test "picking a template re-renders the modal", %{conn: conn} do
      first = create_template("A First")
      second = create_template("B Second", slotted_scene())
      view = mount_page(conn)
      render_click(view, "open_new")
      refute has_element?(view, ~s(form[id="og-wire-slot-form-Title"]))

      view
      |> form("#og-assign-template-form", %{"template_uuid" => second.uuid})
      |> render_change()

      assert has_element?(view, ~s(form[id="og-wire-slot-form-Title"]))
      assert first.uuid != second.uuid
    end

    test "every form with phx-change also carries a phx-submit for the same event", %{conn: conn} do
      create_template("Forms", slotted_scene())
      view = mount_page(conn)
      render_click(view, "open_new")
      pick_group(view, @group_a)

      for slot <- ["Title", "Hero"] do
        view
        |> form(~s(form[id="og-wire-slot-form-#{slot}"]), %{"variable" => "__custom__"})
        |> render_change()
      end

      forms =
        view |> render() |> change_forms() |> Enum.reject(&(&1.id =~ "media-selector-modal"))

      for form <- forms do
        assert form.submit == form.change, "form ##{form.id} has no phx-submit for #{form.change}"
      end

      assert Enum.sort(Enum.map(forms, & &1.id)) ==
               Enum.sort(~w(
                 og-assign-scope-form og-assign-group-form og-assign-template-form
                 og-wire-slot-form-Title og-wire-slot-form-Hero
                 og-wire-slot-custom-form-Title og-wire-slot-media-form-Hero
                 og-preview-group-form og-preview-post-form
               ))
    end

    test "submitting a form (Enter in its field) keeps the unsaved edit", %{conn: conn} do
      create_template("Enter", slotted_scene())
      view = mount_page(conn)
      render_click(view, "open_new")

      view
      |> form(~s(form[id="og-wire-slot-form-Title"]), %{"variable" => "__custom__"})
      |> render_change()

      html =
        view
        |> form(~s(form[id="og-wire-slot-custom-form-Title"]), %{"value" => "Typed"})
        |> render_submit()

      assert html =~ "modal-open"
      assert html =~ ~s(value="Typed")
      assert assignment("default", nil) == nil
    end

    test "the Save and Remove buttons disable themselves while in flight", %{conn: conn} do
      template = create_template("Buttons")
      {:ok, a} = Assignments.create("publishing", "default", nil, template.uuid, %{})
      view = mount_page(conn)

      assert has_element?(
               view,
               ~s(button[phx-click="remove_assignment"][phx-value-id="#{a.uuid}"][phx-disable-with="Removing…"])
             )

      assert has_element?(view, ~s(button[phx-click="save_edit"][phx-disable-with="Saving…"]))
    end
  end

  describe "saving a new assignment" do
    test "creates it with its slot mapping in one activity row against the actor", %{conn: conn} do
      scope = fake_scope()
      template = create_template("New", slotted_scene())
      view = mount_page(conn, scope)
      render_click(view, "open_new")

      view
      |> form(~s(form[id="og-wire-slot-form-Title"]), %{"variable" => "site_name"})
      |> render_change()

      html = render_click(view, "save_edit")

      assert html =~ "Assignment saved."
      refute has_element?(view, "#og-assign-modal.modal-open")

      saved = assignment("default", nil)
      assert saved.template_uuid == template.uuid
      assert saved.slot_mapping == %{"Title" => "site_name"}

      assert [%{actor_uuid: actor, resource_uuid: uuid}] = ActivityRows.rows("assignment.created")
      assert actor == scope.user.uuid
      assert uuid == saved.uuid
      assert ActivityRows.rows("assignment.updated") == []
      assert ActivityRows.rows("assignment.slot_mapping_updated") == []
    end

    test "a group assignment needs a group", %{conn: conn} do
      create_template("Needs Group")
      view = mount_page(conn)
      render_click(view, "open_new")
      view |> form("#og-assign-scope-form", %{"scope" => "group"}) |> render_change()

      assert render_click(view, "save_edit") =~ "Pick a publishing group."
      assert Assignments.list_for_module("publishing") == []
    end

    test "a scope that already has one is refused, with a pointer to its Edit", %{conn: conn} do
      existing_template = create_template("A Existing")
      other_template = create_template("B Other")

      {:ok, existing} =
        Assignments.create("publishing", "group", @group_a, existing_template.uuid, %{})

      view = mount_page(conn)
      render_click(view, "open_new")
      refute has_element?(view, "#og-assign-scope-conflict")

      pick_group(view, @group_a)

      view
      |> form("#og-assign-template-form", %{"template_uuid" => other_template.uuid})
      |> render_change()

      assert has_element?(view, "#og-assign-scope-conflict", "A Existing")
      assert has_element?(view, ~s(button[phx-click="save_edit"][disabled]))

      # The disabled button is not the control: the event is refused too.
      html = render_click(view, "save_edit")
      assert html =~ "This scope already has an assignment. Edit that one instead."

      assert assignment("group", @group_a).template_uuid == existing_template.uuid
      assert ActivityRows.rows("assignment.updated") == []

      # The pointer opens the existing assignment for editing.
      view
      |> element(~s(#og-assign-scope-conflict button[phx-value-id="#{existing.uuid}"]))
      |> render_click()

      assert has_element?(view, "#og-assign-modal h3", "Edit assignment")
      refute has_element?(view, "#og-assign-scope-conflict")
    end

    test "a free group right next to a taken one saves normally", %{conn: conn} do
      template = create_template("Free")
      {:ok, _} = Assignments.create("publishing", "group", @group_a, template.uuid, %{})
      view = mount_page(conn)
      render_click(view, "open_new")
      pick_group(view, @group_b)

      refute has_element?(view, "#og-assign-scope-conflict")
      assert render_click(view, "save_edit") =~ "Assignment saved."
      assert assignment("group", @group_b).template_uuid == template.uuid
    end
  end

  describe "editing an assignment" do
    setup do
      first = create_template("A First", slotted_scene())
      second = create_template("B Second", slotted_scene())
      {:ok, a} = Assignments.create("publishing", "group", @group_a, first.uuid, %{})
      {:ok, b} = Assignments.create("publishing", "group", @group_b, first.uuid, %{})
      %{first: first, second: second, a: a, b: b}
    end

    test "locks scope and group", %{conn: conn, a: a} do
      view = mount_page(conn)
      render_click(view, "open_edit", %{"id" => a.uuid})

      assert has_element?(view, ~s(#og-assign-scope-form select[disabled]))
      assert has_element?(view, ~s(#og-assign-group-form select[disabled]))
    end

    test "a new assignment leaves both selects usable", %{conn: conn} do
      view = mount_page(conn)
      render_click(view, "open_new")
      view |> form("#og-assign-scope-form", %{"scope" => "group"}) |> render_change()

      refute has_element?(view, ~s(#og-assign-scope-form select[disabled]))
      refute has_element?(view, ~s(#og-assign-group-form select[disabled]))
    end

    test "saves the row it opened, once, against the actor", %{conn: conn, a: a, b: b} = ctx do
      scope = fake_scope()
      view = mount_page(conn, scope)
      render_click(view, "open_edit", %{"id" => a.uuid})

      view
      |> form("#og-assign-template-form", %{"template_uuid" => ctx.second.uuid})
      |> render_change()

      view
      |> form(~s(form[id="og-wire-slot-form-Title"]), %{"variable" => "site_name"})
      |> render_change()

      assert render_click(view, "save_edit") =~ "Assignment saved."

      edited = Assignments.get_by_uuid(a.uuid)
      assert edited.scope_uuid == @group_a
      assert edited.template_uuid == ctx.second.uuid
      assert edited.slot_mapping == %{"Title" => "site_name"}

      untouched = Assignments.get_by_uuid(b.uuid)
      assert untouched.template_uuid == ctx.first.uuid
      assert untouched.slot_mapping == %{}

      assert [%{actor_uuid: actor, resource_uuid: uuid}] = ActivityRows.rows("assignment.updated")
      assert actor == scope.user.uuid
      assert uuid == a.uuid
      assert ActivityRows.rows("assignment.slot_mapping_updated") == []
    end

    test "a crafted group or scope change cannot move the edit onto another row",
         %{conn: conn, a: a, b: b} = ctx do
      view = mount_page(conn)
      render_click(view, "open_edit", %{"id" => a.uuid})

      # The selects are disabled, so only a hand-built event can send these.
      render_change(view, "edit_change_group", %{"group_uuid" => @group_b})
      render_change(view, "edit_change_scope", %{"scope" => "default"})

      # The modal still describes the row it opened.
      assert has_element?(view, ~s(#og-assign-scope-form option[value="group"][selected]))

      assert has_element?(
               view,
               ~s(#og-assign-group-form option[value="#{@group_a}"][selected])
             )

      view
      |> form("#og-assign-template-form", %{"template_uuid" => ctx.second.uuid})
      |> render_change()

      render_click(view, "save_edit")

      assert Assignments.get_by_uuid(a.uuid).template_uuid == ctx.second.uuid
      assert Assignments.get_by_uuid(a.uuid).scope_uuid == @group_a
      assert Assignments.get_by_uuid(b.uuid).template_uuid == ctx.first.uuid
      assert assignment("default", nil) == nil
    end

    test "an assignment removed meanwhile reports not found instead of recreating it",
         %{conn: conn, a: a} do
      view = mount_page(conn)
      render_click(view, "open_edit", %{"id" => a.uuid})
      {:ok, _} = Assignments.clear("publishing", "group", @group_a)

      assert render_click(view, "save_edit") =~ "Not found."
      assert assignment("group", @group_a) == nil
    end
  end

  describe "removing an assignment" do
    test "deletes it and logs it against the actor", %{conn: conn} do
      scope = fake_scope()
      template = create_template("Removable")
      {:ok, a} = Assignments.create("publishing", "default", nil, template.uuid, %{})
      view = mount_page(conn, scope)

      html =
        view
        |> element(~s(button[phx-click="remove_assignment"][phx-value-id="#{a.uuid}"]))
        |> render_click()

      assert html =~ "Assignment removed."
      assert Assignments.list_for_module("publishing") == []

      assert [%{actor_uuid: actor, resource_uuid: uuid}] = ActivityRows.rows("assignment.deleted")
      assert actor == scope.user.uuid
      assert uuid == a.uuid
    end
  end

  describe "a custom image value" do
    setup do
      %{template: create_template("Image", slotted_scene())}
    end

    defp open_custom_image(view) do
      render_click(view, "open_new")

      view
      |> form(~s(form[id="og-wire-slot-form-Hero"]), %{"variable" => "__custom__"})
      |> render_change()
    end

    test "the option offers a media file, not a URL", %{conn: conn} do
      view = mount_page(conn)
      html = open_custom_image(view)

      assert html =~ "Custom (pick a media file)"
      refute html =~ "paste a URL"
    end

    for url <- [
          "https://cdn.example/x.png",
          "http://cdn.example/x.png",
          "  https://cdn.example/x.png"
        ] do
      test "#{inspect(url)} is refused at input with a reason", %{conn: conn} do
        view = mount_page(conn)
        open_custom_image(view)

        view
        |> form(~s(form[id="og-wire-slot-media-form-Hero"]), %{"value" => unquote(url)})
        |> render_change()

        assert has_element?(
                 view,
                 ~s([id="og-wire-slot-media-error-Hero"]),
                 "Pick a media file instead"
               )

        render_click(view, "save_edit")
        assert assignment("default", nil).slot_mapping == %{"Hero" => "custom:"}
      end
    end

    test "a media uuid is accepted, and clears an earlier refusal", %{conn: conn} do
      uuid = Ecto.UUID.generate()
      view = mount_page(conn)
      open_custom_image(view)
      media_form = ~s(form[id="og-wire-slot-media-form-Hero"])

      view |> form(media_form, %{"value" => "https://cdn.example/x.png"}) |> render_change()
      view |> form(media_form, %{"value" => uuid}) |> render_change()

      refute has_element?(view, ~s([id="og-wire-slot-media-error-Hero"]))

      render_click(view, "save_edit")
      assert assignment("default", nil).slot_mapping == %{"Hero" => "custom:" <> uuid}
    end

    test "a URL in a TEXT slot is just text", %{conn: conn} do
      view = mount_page(conn)
      render_click(view, "open_new")

      view
      |> form(~s(form[id="og-wire-slot-form-Title"]), %{"variable" => "__custom__"})
      |> render_change()

      view
      |> form(~s(form[id="og-wire-slot-custom-form-Title"]), %{"value" => "https://x.example"})
      |> render_change()

      render_click(view, "save_edit")
      assert assignment("default", nil).slot_mapping == %{"Title" => "custom:https://x.example"}
    end

    test "a URL saved earlier opens without a crash and says it will not render",
         %{conn: conn, template: template} do
      {:ok, a} =
        Assignments.create("publishing", "default", nil, template.uuid, %{
          "Hero" => "custom:https://old.example/legacy.png"
        })

      view = mount_page(conn)
      html = render_click(view, "open_edit", %{"id" => a.uuid})

      assert html =~ "https://old.example/legacy.png"
      assert has_element?(view, ~s([id="og-wire-slot-media-error-Hero"]))

      # Clearing it removes the warning; the rest of the assignment still saves.
      view
      |> element(~s(button[phx-click="clear_slot_custom"][phx-value-slot="Hero"]))
      |> render_click()

      refute has_element?(view, ~s([id="og-wire-slot-media-error-Hero"]))

      assert render_click(view, "save_edit") =~ "Assignment saved."
      assert Assignments.get_by_uuid(a.uuid).slot_mapping == %{"Hero" => "custom:"}
    end
  end

  describe "handle_info/2" do
    setup do
      %{template: create_template("Info", slotted_scene())}
    end

    test "a picked media file becomes the slot's custom value", %{conn: conn} do
      uuid = Ecto.UUID.generate()
      view = mount_page(conn)
      render_click(view, "open_new")
      render_click(view, "open_slot_media_picker", %{"slot" => "Hero"})

      send(view.pid, {:media_selected, [uuid]})
      render_click(view, "save_edit")

      assert assignment("default", nil).slot_mapping == %{"Hero" => "custom:" <> uuid}
    end

    test "an empty selection changes nothing", %{conn: conn} do
      view = mount_page(conn)
      render_click(view, "open_new")
      render_click(view, "open_slot_media_picker", %{"slot" => "Hero"})

      send(view.pid, {:media_selected, []})
      render_click(view, "save_edit")

      assert assignment("default", nil).slot_mapping == %{}
    end

    test "closing the picker forgets its slot", %{conn: conn} do
      view = mount_page(conn)
      render_click(view, "open_new")
      render_click(view, "open_slot_media_picker", %{"slot" => "Hero"})

      send(view.pid, {:media_selector_closed})
      # With the slot gone, a late selection has nowhere to land.
      send(view.pid, {:media_selected, [Ecto.UUID.generate()]})
      render_click(view, "save_edit")

      assert assignment("default", nil).slot_mapping == %{}
    end

    test "an unexpected message is ignored and the page keeps working", %{conn: conn} do
      view = mount_page(conn)

      send(view.pid, {:something, :unexpected})

      assert render_click(view, "open_new") =~ "modal-open"
    end
  end

  describe "the preview source" do
    test "picking a group lists its posts and defaults to a published one", %{conn: conn} do
      create_template("Preview", slotted_scene())
      draft = Publishing.post(%{metadata: %{title: "Draft one", status: "draft"}})
      live_post = Publishing.post(%{metadata: %{title: "Live one", status: "published"}})
      Publishing.put_posts("beta", [draft, live_post])

      view = mount_page(conn)
      render_click(view, "open_new")

      html = view |> form("#og-preview-group-form", %{"group_slug" => "beta"}) |> render_change()

      assert html =~ "Draft one (draft)"

      assert has_element?(
               view,
               ~s(#og-preview-post-form option[value="#{live_post.uuid}"][selected])
             )

      view |> form("#og-preview-post-form", %{"post_uuid" => draft.uuid}) |> render_change()
      assert has_element?(view, ~s(#og-preview-post-form option[value="#{draft.uuid}"][selected]))
    end
  end
end
