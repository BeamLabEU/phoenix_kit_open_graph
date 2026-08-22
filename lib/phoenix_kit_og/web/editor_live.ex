defmodule PhoenixKitOG.Web.EditorLive do
  @moduledoc """
  The OG template editor — OpenFresco's server-authoritative editor
  stage on the left, this module's chrome around it: toolbar + insert
  menu, slots panel, property panel, and the always-on preview pane.

  ## Division of labor (since the OpenFresco switch)

  - **`OpenFresco.Editor`** (LiveComponent) owns the stage: it renders
    the scene via `OpenFresco.render_svg/3` (measured text — the same
    layout the PNG render uses, so WYSIWYG holds by construction) and
    applies pointer gestures (select/drag/resize/front/delete) through
    `OpenFresco.Editor.Ops`, notifying us with
    `{:open_fresco_editor, id, {:scene_changed | :selected, _}}`.
  - **This LV** owns the scene document (loads/saves it on the
    template row via `SceneStore`, lazily migrating legacy canvases),
    the property panel (`SceneEdit` mutations), the insert menu,
    keyboard nudges, the media picker, autosave, and the preview pane.

  ## Save semantics

  Changes are autosaved on a 800ms debounce. Manual save via `Ctrl+S`
  or the "Save" button flushes immediately. A header pill shows
  saved / saving / unsaved state.
  """

  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitOG.Gettext

  # Sets up the file-upload allowlist + `validate` event stub + parent
  # `handle_info` delegator for MediaSelectorModal to work. Zero
  # boilerplate on our side.
  use PhoenixKitWeb.Components.MediaBrowser.Embed

  require Logger

  alias OpenFresco.Editor.Ops
  alias PhoenixKitOG.{Errors, Paths, SceneEdit, SceneStore, Templates, Variables}
  alias PhoenixKitOG.Render.Media
  alias PhoenixKitOG.Schemas.Template
  alias PhoenixKitOG.Web.StagePlaceholder

  @stage_id "og-editor-stage"

  @impl true
  def mount(params, _session, socket) do
    case load_or_create_template(params, socket.assigns.live_action, socket) do
      {:ok, template} ->
        # Every OG card is 1200×630 (the universal 1.91:1 social-card
        # size) — a stray custom-sized scene snaps back on edit.
        scene = template.canvas |> SceneStore.load() |> OpenFresco.Scene.put_size(1200, 630)

        socket =
          socket
          |> assign(
            :page_title,
            gettext("OpenGraph — %{name}", name: template.name || gettext("Editor"))
          )
          |> assign(:template, template)
          |> assign(:scene, scene)
          |> assign(:stage_id, @stage_id)
          |> assign(:selected_id, nil)
          |> assign(:selected_ids, [])
          |> assign(:slots, SceneStore.slots(scene))
          |> assign(:stage_preview, true)
          |> assign(:stage_values, stage_values(SceneStore.slots(scene), true))
          |> assign(:media_resolver, Media.resolver())
          |> assign(:preview_platform, "card")
          |> assign(:save_state, :saved)
          |> assign(:autosave_timer, nil)
          |> assign(:show_media_selector, false)
          |> assign(:media_selection_mode, :single)
          |> assign(:media_selected_uuids, [])
          |> assign(:media_selector_target, nil)
          |> assign(
            :global_values,
            Variables.global_values(%{
              endpoint: socket.endpoint,
              language: socket.assigns[:current_locale] || ""
            })
          )

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, Errors.message(:not_found))
         |> push_navigate(to: Paths.templates())}
    end
  end

  # =========================================================================
  # Events — toolbar / element library
  # =========================================================================

  @impl true
  def handle_event("insert", %{"kind" => kind}, socket) do
    {scene, id} = SceneEdit.insert(socket.assigns.scene, kind)

    {:noreply,
     socket
     |> put_scene(scene)
     |> assign(:selected_id, id)}
  end

  def handle_event("update_canvas", %{"field" => "bg_type", "value" => type}, socket) do
    {:noreply, put_scene(socket, SceneEdit.switch_background(socket.assigns.scene, type))}
  end

  def handle_event("update_canvas", %{"field" => field, "value" => value}, socket) do
    {:noreply, put_scene(socket, SceneEdit.update_canvas(socket.assigns.scene, field, value))}
  end

  # =========================================================================
  # Media picker — opens the shared MediaSelectorModal for a field.
  #
  # `target` says where the picked UUID should land:
  #   - "background_value" → canvas background image fill value
  #   - "element_src"      → the currently selected image element's value
  # =========================================================================

  def handle_event("open_media_picker", %{"target" => target}, socket) do
    {:noreply,
     socket
     |> assign(:media_selector_target, target)
     |> assign(:show_media_selector, true)}
  end

  def handle_event("clear_media_field", %{"target" => "background_value"}, socket) do
    {:noreply,
     put_scene(socket, SceneEdit.update_canvas(socket.assigns.scene, "bg_image_value", ""))}
  end

  def handle_event("clear_media_field", %{"target" => "element_src"}, socket) do
    case socket.assigns.selected_id do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, "value", ""))}
    end
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, id)}
  end

  def handle_event("deselect", _params, socket) do
    {:noreply, assign(socket, :selected_id, nil)}
  end

  def handle_event("delete_selected", _params, socket) do
    case selection(socket) do
      [] ->
        {:noreply, socket}

      ids ->
        {:noreply,
         socket
         |> put_scene(Ops.delete_many(socket.assigns.scene, ids))
         |> assign(:selected_id, nil)
         |> assign(:selected_ids, [])}
    end
  end

  def handle_event("bring_to_front", _params, socket) do
    if id = socket.assigns.selected_id do
      {:noreply, put_scene(socket, Ops.bring_to_front(socket.assigns.scene, id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("send_to_back", _params, socket) do
    if id = socket.assigns.selected_id do
      {:noreply, put_scene(socket, SceneEdit.send_to_back(socket.assigns.scene, id))}
    else
      {:noreply, socket}
    end
  end

  # The stage doubles as the preview: sample values (and the arrows
  # stand-in for image slots) substitute by default; toggling off shows
  # the raw {{slot}} / [[global]] tokens for authors who want them.
  def handle_event("toggle_stage_preview", _params, socket) do
    preview? = !socket.assigns.stage_preview

    {:noreply,
     socket
     |> assign(:stage_preview, preview?)
     |> assign(:stage_values, stage_values(socket.assigns.slots, preview?))}
  end

  # The platform tabs wrap the live stage in each platform's chrome —
  # the card is the same 1.91:1 everywhere, so no separate render.
  @preview_platforms ~w(card facebook x linkedin discord)

  def handle_event("set_preview_platform", %{"tab" => platform}, socket)
      when platform in @preview_platforms do
    {:noreply, assign(socket, :preview_platform, platform)}
  end

  def handle_event("set_preview_platform", _params, socket), do: {:noreply, socket}

  # =========================================================================
  # Events — property panel
  # =========================================================================

  # Forms in the property panel carry `el_id`, `field`, and `value` as
  # hidden+visible inputs. The hidden field name is `el_id` (not `id`)
  # so the HTML form element id doesn't get clobbered.
  def handle_event(
        "update_prop",
        %{"el_id" => id, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, field, value))}
  end

  # Checkbox variant (no `value` key when unchecked).
  def handle_event("update_prop", %{"el_id" => id, "field" => field} = params, socket) do
    value = Map.get(params, "value", "false")

    {:noreply,
     put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, field, value))}
  end

  # Variable-name variant — the property panel shows the bare `name`
  # inside static `{{` / `}}` decorations; this wraps the typed value
  # into the canonical slot syntax before writing.
  def handle_event(
        "update_prop_variable",
        %{"el_id" => id, "field" => field, "value" => value},
        socket
      ) do
    wrapped = if value == "", do: "", else: "{{#{String.trim(value)}}}"

    {:noreply,
     put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, field, wrapped))}
  end

  # Image-source mode toggle in the property panel. Constant clears the
  # slot value so the media picker reappears; Variable seeds a fresh
  # `{{ImageN}}` slot name so we don't collide with an existing slot.
  def handle_event("set_image_mode", %{"el_id" => id, "mode" => "constant"}, socket) do
    {:noreply, put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, "value", ""))}
  end

  def handle_event("set_image_mode", %{"el_id" => id, "mode" => "variable"}, socket) do
    name = SceneEdit.next_slot_name(socket.assigns.scene, "Image")

    {:noreply,
     put_scene(socket, SceneEdit.update_element(socket.assigns.scene, id, "value", "{{#{name}}}"))}
  end

  def handle_event("update_template_name", %{"name" => name}, socket) do
    template = socket.assigns.template

    case Templates.update(template, %{"name" => name}, actor_opts(socket)) do
      {:ok, template} ->
        {:noreply,
         socket
         |> assign(:template, template)
         |> assign(:page_title, gettext("OpenGraph — %{name}", name: template.name))}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, gettext("Could not rename template."))}
    end
  end

  # =========================================================================
  # Events — keyboard
  # =========================================================================

  def handle_event("nudge", %{"key" => key, "shift" => shift?}, socket) do
    case socket.assigns.selected_id do
      nil ->
        {:noreply, socket}

      _id ->
        step = if shift?, do: 10, else: 1
        {dx, dy} = nudge_delta(key, step)

        {:noreply,
         put_scene(socket, Ops.move_many(socket.assigns.scene, selection(socket), dx, dy))}
    end
  end

  def handle_event("save_now", _params, socket), do: do_save(socket)

  # =========================================================================
  # Autosave plumbing + stage notifications
  # =========================================================================

  @impl true
  def handle_info(:autosave, socket), do: do_save(socket)

  # The OpenFresco stage applied a pointer edit (drag/resize/front/
  # delete) — adopt its scene as ours and autosave. No put_scene/2 here:
  # the component already re-rendered itself.
  def handle_info({:open_fresco_editor, @stage_id, {:scene_changed, scene}}, socket) do
    slots = SceneStore.slots(scene)

    {:noreply,
     socket
     |> assign(:scene, scene)
     |> assign(:slots, slots)
     |> assign(:stage_values, stage_values(slots, socket.assigns.stage_preview))
     |> mark_dirty()}
  end

  def handle_info({:open_fresco_editor, @stage_id, {:selected, id}}, socket) do
    {:noreply, socket |> assign(:selected_id, id) |> assign(:selected_ids, List.wrap(id))}
  end

  # Multi-select (shift-click / marquee): the property panel follows the
  # last-selected element; group actions (delete, nudge) apply to the set.
  def handle_info({:open_fresco_editor, @stage_id, {:selected_ids, ids}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_ids, ids)
     |> assign(:selected_id, List.last(ids))}
  end

  # MediaSelectorModal → parent: user confirmed a selection.
  def handle_info({:media_selected, file_uuids}, socket) do
    file_uuid = List.first(file_uuids || [])
    target = socket.assigns.media_selector_target

    cond do
      is_nil(file_uuid) or is_nil(target) ->
        {:noreply, close_media_selector(socket)}

      target == "background_value" ->
        {:noreply,
         socket
         |> put_scene(SceneEdit.update_canvas(socket.assigns.scene, "bg_image_value", file_uuid))
         |> close_media_selector()}

      target == "element_src" and is_binary(socket.assigns.selected_id) ->
        {:noreply,
         socket
         |> put_scene(
           SceneEdit.update_element(
             socket.assigns.scene,
             socket.assigns.selected_id,
             "value",
             file_uuid
           )
         )
         |> close_media_selector()}

      true ->
        {:noreply, close_media_selector(socket)}
    end
  end

  def handle_info({:media_selector_closed}, socket), do: {:noreply, close_media_selector(socket)}

  # Catch-all: this LV arms an :autosave timer and attaches MediaBrowser
  # hooks, so a late/stray message must not crash it with FunctionClauseError.
  def handle_info(msg, socket) do
    Logger.debug("[PhoenixKitOG.EditorLive] unexpected handle_info: #{inspect(msg)}")
    {:noreply, socket}
  end

  # =========================================================================
  # Helpers
  # =========================================================================

  # Sample values for the stage's preview mode: text slots read
  # "Sample <name>", image slots get the arrows stand-in (browser-only
  # — see StagePlaceholder's moduledoc). Raw mode substitutes nothing.
  defp stage_values(slots, true) do
    Enum.into(slots, %{}, fn
      %{name: name, type: :image} -> {name, StagePlaceholder.data_url()}
      %{name: name} -> {name, "Sample #{name}"}
    end)
  end

  defp stage_values(_slots, false), do: %{}

  # The current selection set — the multi-select list when one is
  # active, else the single selected id.
  defp selection(socket) do
    case socket.assigns.selected_ids do
      [_ | _] = ids -> ids
      _ -> List.wrap(socket.assigns.selected_id)
    end
  end

  # Every panel-side scene mutation flows through here: adopt the new
  # scene, refresh the slots panel, arm autosave + preview refresh.
  defp put_scene(socket, scene) do
    slots = SceneStore.slots(scene)

    socket
    |> assign(:scene, scene)
    |> assign(:slots, slots)
    |> assign(:stage_values, stage_values(slots, socket.assigns.stage_preview))
    |> mark_dirty()
  end

  defp close_media_selector(socket) do
    socket
    |> assign(:show_media_selector, false)
    |> assign(:media_selector_target, nil)
  end

  defp do_save(socket) do
    if socket.assigns.autosave_timer, do: Process.cancel_timer(socket.assigns.autosave_timer)

    case Templates.update(
           socket.assigns.template,
           %{"canvas" => SceneStore.dump(socket.assigns.scene)},
           # Autosaves happen on a timer, not a user click — mark them
           # `mode: "auto"` in the activity feed so manual saves stay
           # distinguishable.
           Keyword.put(actor_opts(socket), :mode, "auto")
         ) do
      {:ok, template} ->
        {:noreply,
         socket
         |> assign(:template, template)
         |> assign(:save_state, :saved)
         |> assign(:autosave_timer, nil)}

      {:error, _cs} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Save failed — please retry."))
         |> assign(:save_state, :error)}
    end
  end

  defp actor_opts(socket) do
    case socket.assigns[:phoenix_kit_current_user] do
      %{uuid: uuid} -> [actor_uuid: uuid]
      _ -> []
    end
  end

  defp mark_dirty(socket) do
    if socket.assigns.autosave_timer, do: Process.cancel_timer(socket.assigns.autosave_timer)
    timer = Process.send_after(self(), :autosave, 800)

    socket
    |> assign(:save_state, :dirty)
    |> assign(:autosave_timer, timer)
  end

  # =========================================================================
  # Loading
  # =========================================================================

  # `mount/3` runs once for the disconnected (static HTML) render and
  # again for the connected (WebSocket) render. Only create the row on
  # the connected pass — otherwise every fresh visit to `/new` (a full
  # page load, not a `push_navigate` from an already-connected LV)
  # leaves an orphaned blank template behind from the disconnected
  # render nobody ever sees.
  defp load_or_create_template(_params, :new, socket) do
    if connected?(socket) do
      name = "Untitled #{System.unique_integer([:positive])}"
      # The actor is threaded later on the first save. Activity feed
      # shows an anonymous `template.created` for the initial insert.
      Templates.create(%{"name" => name, "canvas" => SceneStore.dump(SceneStore.blank())})
    else
      {:ok, %Template{canvas: SceneStore.dump(SceneStore.blank())}}
    end
  end

  defp load_or_create_template(%{"uuid" => uuid}, :edit, _socket) do
    case Templates.get(uuid) do
      nil -> {:error, :not_found}
      %Template{} = t -> {:ok, t}
    end
  end

  defp nudge_delta("ArrowLeft", step), do: {-step, 0}
  defp nudge_delta("ArrowRight", step), do: {step, 0}
  defp nudge_delta("ArrowUp", step), do: {0, -step}
  defp nudge_delta("ArrowDown", step), do: {0, step}
  defp nudge_delta(_, _), do: {0, 0}

  # =========================================================================
  # Render — delegated to a colocated template for sanity
  # =========================================================================

  @impl true
  def render(assigns) do
    PhoenixKitOG.Web.EditorLive.Template.render(assigns)
  end
end
