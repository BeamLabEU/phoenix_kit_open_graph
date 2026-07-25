defmodule PhoenixKitOG.Web.EditorLive.Template do
  @moduledoc """
  HEEx render template for the OG editor. Split out from the LV module
  so the event-handler code stays scannable.

  The layout is:

      ┌───────────────────────────────────────────────────┐
      │  Toolbar: name | save state | insert | preview |save│
      ├──────────────────────────────┬────────────────────┤
      │  OpenFresco.Editor stage     │  Slots used        │
      │  (server-authoritative SVG,  │  Selected props /  │
      │   drag/resize/delete)        │  template props    │
      ├──────────────────────────────┤                    │
      │  Always-on preview pane      │                    │
      └──────────────────────────────┴────────────────────┘

  The stage is OpenFresco's LiveComponent; everything around it is
  ours. Property-panel forms all post `update_prop`/`update_canvas`
  events handled by the LV through `PhoenixKitOG.SceneEdit`.
  """

  use PhoenixKitWeb, :html
  use Gettext, backend: PhoenixKitOG.Gettext

  alias Phoenix.LiveView.JS
  alias PhoenixKitOG.Paths

  def render(assigns) do
    assigns =
      assign_new(assigns, :selected, fn ->
        assigns.selected_id &&
          Enum.find(assigns.scene.elements, &(&1.id == assigns.selected_id))
      end)

    ~H"""
    <div
      id="phoenix-kit-og-editor"
      phx-hook="PhoenixKitOGEditor"
      phx-window-keydown="nudge"
      phx-key="ArrowUp"
      class="w-full h-[calc(100vh-8rem)] flex flex-col bg-base-200"
    >
      <.toolbar
        template={@template}
        save_state={@save_state}
        preview_visible={@preview_visible}
        selected={@selected}
      />

      <div class="flex-1 flex overflow-hidden">
        <div class="flex-1 flex flex-col overflow-hidden min-w-0">
          <main class="flex-1 overflow-auto bg-base-200 p-8 flex flex-col items-center gap-4">
            <noscript>
              <div class="rounded-lg border border-error/40 bg-error/10 text-error px-4 py-2 text-sm max-w-2xl">
                {gettext(
                  "JavaScript is disabled — the template editor needs it for dragging, resizing, and saving. Enable JS and reload."
                )}
              </div>
            </noscript>

            <div class="shadow-lg border border-base-300 bg-base-100 max-w-full overflow-auto">
              <.live_component
                module={OpenFresco.Editor}
                id={@stage_id}
                scene={@scene}
                values={%{}}
              />
            </div>

            <p class="text-xs text-base-content/40">
              {gettext(
                "Drag to move, corner handles to resize, Delete removes. Slot tokens render as-is here — the preview below substitutes sample values."
              )}
            </p>
          </main>

          <.preview_pane
            :if={@preview_visible}
            loading={@preview_loading}
            url={@preview_url}
            error={@preview_error}
            platform={@preview_platform}
            global_values={@global_values}
          />
        </div>

        <.right_panel selected={@selected} slots={@slots} scene={@scene} />
      </div>

      <%!-- Media picker modal (shared with the publishing editor pattern):
           when open, hosts the full MediaBrowser inside a modal; user
           confirms → parent gets {:media_selected, [uuid]}. --%>
      <.live_component
        module={PhoenixKitWeb.Live.Components.MediaSelectorModal}
        id="og-media-selector-modal"
        show={@show_media_selector}
        mode={@media_selection_mode}
        selected_uuids={@media_selected_uuids}
        file_type_filter={:image}
        phoenix_kit_current_user={assigns[:phoenix_kit_current_user]}
      />
    </div>
    """
  end

  # =========================================================================
  # Preview pane — the always-on strip under the stage. Renders the
  # current template as a PNG and shows it either raw ("Card") or inside
  # a platform mockup, one platform per tab. Toggleable from the toolbar.
  # =========================================================================
  attr(:loading, :boolean, default: false)
  attr(:url, :string, default: nil)
  attr(:error, :string, default: nil)
  attr(:platform, :string, required: true)
  attr(:global_values, :map, required: true)

  defp preview_pane(assigns) do
    assigns =
      assigns
      |> assign_new(:site_host, fn ->
        Map.get(assigns.global_values, "site_host", "example.com")
      end)
      |> assign_new(:site_name, fn ->
        Map.get(assigns.global_values, "site_name", "Example Site")
      end)
      |> assign_new(:sample_title, fn -> gettext("Sample Post Title") end)
      |> assign_new(:sample_desc, fn ->
        gettext(
          "This is a sample post description — the way readers will see the intro before they click through."
        )
      end)

    ~H"""
    <section class="shrink-0 max-h-[45%] flex flex-col border-t border-base-300 bg-base-100">
      <header class="flex items-center gap-3 px-4 py-1.5 border-b border-base-300/60">
        <h3
          class="text-xs font-semibold text-base-content/70 uppercase tracking-wide cursor-help"
          title={
            gettext(
              "How this template will appear when shared. Slot values here are placeholder previews — real posts substitute their own values at render time."
            )
          }
        >
          {gettext("Preview")}
        </h3>
        <span :if={@loading} class="loading loading-spinner loading-xs text-base-content/40"></span>

        <div class="tabs tabs-boxed tabs-sm bg-base-200 p-0.5 ml-auto">
          <button
            :for={{key, label} <- platform_tabs()}
            type="button"
            phx-click="set_preview_platform"
            phx-value-platform={key}
            class={["tab tab-sm", @platform == key && "tab-active"]}
          >
            {label}
          </button>
        </div>

        <button
          type="button"
          phx-click="toggle_preview_pane"
          class="btn btn-ghost btn-xs"
          title={gettext("Hide preview")}
        >
          <.icon name="hero-eye-slash" class="w-3.5 h-3.5" />
        </button>
      </header>

      <div class="flex-1 overflow-auto p-4">
        <div :if={@error} class="mx-auto max-w-2xl mb-3">
          <div class="rounded-md border border-error/30 bg-error/5 px-4 py-3 text-sm text-error">
            {@error}
          </div>
        </div>

        <div
          :if={is_nil(@url) and is_nil(@error)}
          class="flex items-center justify-center gap-3 py-10 text-base-content/60"
        >
          <span class="loading loading-spinner loading-md"></span>
          <span class="text-sm">{gettext("Rendering preview…")}</span>
        </div>

        <div :if={@url} class={["mx-auto", (@platform == "card" && "max-w-2xl") || "max-w-md"]}>
          <div :if={@platform == "card"}>
            <img
              src={@url}
              alt={gettext("OG preview")}
              class="w-full rounded border border-base-300 shadow-sm"
              loading="lazy"
            />
            <p class="text-xs text-base-content/50 mt-1.5 text-center">
              {gettext("Rendered image (1200 × 630)")}
            </p>
          </div>

          <div
            :if={@platform != "card"}
            class="rounded-lg border border-base-300 bg-base-100 overflow-hidden"
          >
            <.fb_card
              :if={@platform == "facebook"}
              image={@url}
              title={@sample_title}
              description={@sample_desc}
              host={@site_host}
            />
            <.twitter_card
              :if={@platform == "x"}
              image={@url}
              title={@sample_title}
              description={@sample_desc}
              host={@site_host}
            />
            <.linkedin_card
              :if={@platform == "linkedin"}
              image={@url}
              title={@sample_title}
              description={@sample_desc}
              host={@site_host}
            />
            <.discord_card
              :if={@platform == "discord"}
              image={@url}
              title={@sample_title}
              description={@sample_desc}
              host={@site_host}
              site_name={@site_name}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  # Tab keys must stay in sync with the LV's @preview_platforms whitelist.
  defp platform_tabs do
    [
      {"card", gettext("Card")},
      {"facebook", "Facebook"},
      {"x", "X (Twitter)"},
      {"linkedin", "LinkedIn"},
      {"discord", "Discord / Slack"}
    ]
  end

  attr(:image, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:host, :string, required: true)

  defp fb_card(assigns) do
    ~H"""
    <div>
      <img src={@image} alt="" class="w-full aspect-[1.91/1] object-cover" />
      <div class="bg-[#f0f2f5] px-3 py-2 border-t border-base-300">
        <p class="text-[10px] uppercase text-neutral-500 truncate">{@host}</p>
        <p class="text-sm font-semibold text-neutral-900 leading-snug line-clamp-2">{@title}</p>
        <p class="text-xs text-neutral-500 leading-snug line-clamp-2 mt-0.5">{@description}</p>
      </div>
    </div>
    """
  end

  attr(:image, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:host, :string, required: true)

  defp twitter_card(assigns) do
    ~H"""
    <div class="border border-neutral-300 rounded-2xl overflow-hidden">
      <img src={@image} alt="" class="w-full aspect-[1.91/1] object-cover" />
      <div class="bg-white px-3 py-2 border-t border-neutral-200">
        <p class="text-xs text-neutral-500">{@host}</p>
        <p class="text-sm text-neutral-900 leading-snug line-clamp-2">{@title}</p>
      </div>
    </div>
    """
  end

  attr(:image, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:host, :string, required: true)

  defp linkedin_card(assigns) do
    ~H"""
    <div>
      <img src={@image} alt="" class="w-full aspect-[1.91/1] object-cover" />
      <div class="bg-white px-3 py-2 border-t border-neutral-200">
        <p class="text-sm font-semibold text-neutral-900 leading-snug line-clamp-2">{@title}</p>
        <p class="text-xs text-neutral-500 mt-1 truncate">{@host}</p>
      </div>
    </div>
    """
  end

  attr(:image, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:host, :string, required: true)
  attr(:site_name, :string, required: true)

  defp discord_card(assigns) do
    ~H"""
    <div class="bg-[#2b2d31] p-3 border-l-4 border-l-[#5865f2]">
      <p class="text-[11px] text-[#f2f3f5]/70">{@site_name}</p>
      <p class="text-sm text-[#00a8fc] font-semibold leading-snug line-clamp-1 mt-0.5">{@title}</p>
      <p class="text-xs text-[#dbdee1] mt-1 line-clamp-3">{@description}</p>
      <img src={@image} alt="" class="w-full rounded mt-2 aspect-[1.91/1] object-cover" />
    </div>
    """
  end

  # =========================================================================
  # Toolbar
  # =========================================================================

  defp toolbar(assigns) do
    ~H"""
    <header class="flex items-center justify-between gap-4 px-4 py-2 bg-base-100 border-b border-base-300">
      <div class="flex items-center gap-2 flex-1 min-w-0">
        <.link navigate={Paths.templates()} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
        </.link>
        <form phx-change="update_template_name" class="flex-1 min-w-0">
          <input
            type="text"
            name="name"
            value={@template.name}
            class="input input-ghost input-sm w-full font-semibold text-base"
            placeholder={gettext("Untitled template")}
          />
        </form>
        <.save_pill state={@save_state} />
      </div>

      <div class="flex items-center gap-1">
        <.insert_menu />

        <div class="divider divider-horizontal mx-0" />

        <div :if={@selected} class="flex items-center gap-1">
          <button
            type="button"
            phx-click="bring_to_front"
            class="btn btn-ghost btn-sm"
            title={gettext("Bring to front")}
          >
            <.icon name="hero-arrow-up-on-square-stack" class="w-4 h-4" />
          </button>
          <button
            type="button"
            phx-click="send_to_back"
            class="btn btn-ghost btn-sm"
            title={gettext("Send to back")}
          >
            <.icon name="hero-arrow-down-on-square-stack" class="w-4 h-4" />
          </button>
          <button
            type="button"
            phx-click="delete_selected"
            class="btn btn-ghost btn-sm text-error"
            title={gettext("Delete element")}
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
          <div class="divider divider-horizontal mx-0" />
        </div>

        <button
          type="button"
          phx-click="toggle_preview_pane"
          class={["btn btn-ghost btn-sm", @preview_visible && "btn-active"]}
          title={
            if @preview_visible,
              do: gettext("Hide the live preview pane"),
              else: gettext("Show the live preview pane")
          }
        >
          <.icon name={(@preview_visible && "hero-eye") || "hero-eye-slash"} class="w-4 h-4 mr-1" />
          {gettext("Preview")}
        </button>

        <button
          type="button"
          phx-click="save_now"
          phx-disable-with={gettext("Saving…")}
          class="btn btn-primary btn-sm"
        >
          <.icon name="hero-bookmark" class="w-4 h-4 mr-1" /> {gettext("Save")}
        </button>
      </div>
    </header>
    """
  end

  # ==============================================================
  # Insert dropdown. Wraps `<details class="dropdown">` so it closes on
  # outside click automatically; each item pushes the insert event and
  # removes the `open` attribute so the menu collapses.
  # ==============================================================
  defp insert_menu(assigns) do
    ~H"""
    <details
      id="insert-menu"
      class="dropdown"
      phx-click-away={JS.remove_attribute("open", to: "#insert-menu")}
    >
      <summary class="btn btn-primary btn-sm">
        <.icon name="hero-plus" class="w-4 h-4 mr-1" /> {gettext("Insert…")}
      </summary>
      <ul class="dropdown-content menu bg-base-100 rounded-box shadow-lg z-10 w-64 p-2 mt-1">
        <li class="menu-title"><span>{gettext("Text")}</span></li>
        <li>
          <a phx-click={insert_and_close("text")}>
            <.icon name="hero-bars-3-bottom-left" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Static text")}</div>
              <div class="text-xs text-base-content/50">{gettext("You type the content.")}</div>
            </div>
          </a>
        </li>
        <li>
          <a phx-click={insert_and_close("text_var")}>
            <.icon name="hero-variable" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Text variable")}</div>
              <div class="text-xs text-base-content/50">
                {gettext(~S|A {{TextN}} slot to wire later.|)}
              </div>
            </div>
          </a>
        </li>

        <li class="menu-title mt-1"><span>{gettext("Image")}</span></li>
        <li>
          <a phx-click={insert_and_close("image")}>
            <.icon name="hero-photo" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Static image")}</div>
              <div class="text-xs text-base-content/50">{gettext("Pick from the media library.")}</div>
            </div>
          </a>
        </li>
        <li>
          <a phx-click={insert_and_close("image_var")}>
            <.icon name="hero-variable" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Image variable")}</div>
              <div class="text-xs text-base-content/50">
                {gettext(~S|An {{ImageN}} slot to wire later.|)}
              </div>
            </div>
          </a>
        </li>

        <li class="menu-title mt-1"><span>{gettext("Shape & button")}</span></li>
        <li>
          <a phx-click={insert_and_close("rect")}>
            <.icon name="hero-rectangle-group" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Rectangle")}</div>
              <div class="text-xs text-base-content/50">
                {gettext("Solid fill, rounded corners.")}
              </div>
            </div>
          </a>
        </li>
        <li>
          <a phx-click={insert_and_close("button")}>
            <.icon name="hero-cursor-arrow-ripple" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Call-to-action button")}</div>
              <div class="text-xs text-base-content/50">
                {gettext("Auto-sizes to its translatable label.")}
              </div>
            </div>
          </a>
        </li>
        <li>
          <a phx-click={insert_and_close("stamp")}>
            <.icon name="hero-tag" class="w-4 h-4" />
            <div class="flex-1">
              <div>{gettext("Stamp")}</div>
              <div class="text-xs text-base-content/50">{gettext("A short badge/label.")}</div>
            </div>
          </a>
        </li>

        <li class="menu-title mt-1"><span>{gettext("Site globals")}</span></li>
        <li :for={
          global <- ["site_url", "site_host", "site_name", "page_url", "page_locale"]
        }>
          <a phx-click={insert_and_close("global:" <> global)}>
            <.icon name="hero-globe-alt" class="w-4 h-4" />
            <span class="font-mono text-xs">[[{global}]]</span>
          </a>
        </li>
      </ul>
    </details>
    """
  end

  defp insert_and_close(kind) do
    JS.push("insert", value: %{kind: kind})
    |> JS.remove_attribute("open", to: "#insert-menu")
  end

  defp save_pill(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm whitespace-nowrap",
      @state == :saved && "badge-ghost",
      @state == :dirty && "badge-warning",
      @state == :error && "badge-error"
    ]}>
      <%= case @state do %>
        <% :saved -> %>
          {gettext("Saved")}
        <% :dirty -> %>
          {gettext("Unsaved…")}
        <% :error -> %>
          {gettext("Save failed")}
      <% end %>
    </span>
    """
  end

  # =========================================================================
  # Right panel
  # =========================================================================

  defp right_panel(assigns) do
    ~H"""
    <aside class="w-80 bg-base-100 border-l border-base-300 overflow-y-auto p-4 space-y-4">
      <.slots_panel slots={@slots} />
      <hr class="border-base-300" />
      <%= if @selected do %>
        <.property_panel selected={@selected} scene={@scene} />
      <% else %>
        <.template_props scene={@scene} />
      <% end %>
    </aside>
    """
  end

  # Small at-a-glance list of slot names the author has declared so far.
  defp slots_panel(assigns) do
    ~H"""
    <section class="space-y-2">
      <header class="flex items-center justify-between">
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
          {gettext("Slots used")}
        </h3>
        <span class="text-xs text-base-content/40">{length(@slots)}</span>
      </header>
      <%= if @slots == [] do %>
        <p class="text-xs text-base-content/50">
          {gettext(
            ~S|Type {{name}} in a text field (or make an element a Variable) to declare a slot. Wire it to real data on the Assignments page.|
          )}
        </p>
      <% else %>
        <ul class="flex flex-wrap gap-1.5">
          <li :for={s <- @slots} class="badge badge-outline gap-1">
            <span class="text-xs text-base-content/50">{icon_for_type(s.type)}</span>
            <span class="font-mono text-xs">{s.name}</span>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  defp icon_for_type(:text), do: "T"
  defp icon_for_type(:image), do: "\u{1F5BC}"
  defp icon_for_type(_), do: "?"

  # ==============================================================
  # Template properties — shown when no element is selected. Canvas
  # size + the background fill with Solid / Image / Gradient tabs.
  # ==============================================================
  attr(:scene, :map, required: true)

  defp template_props(assigns) do
    bg = assigns.scene.canvas.background || %{type: :solid, color: "#0b1220"}
    bg_type = Map.get(bg, :type, :solid)

    assigns =
      assigns
      |> assign(:bg, bg)
      |> assign(:bg_type, bg_type)

    ~H"""
    <div class="space-y-4">
      <h2 class="font-semibold text-base">{gettext("Template")}</h2>

      <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
        <header class="flex items-center gap-1.5">
          <.icon name="hero-viewfinder-circle" class="w-3.5 h-3.5 text-base-content/50" />
          <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
            {gettext("Canvas")}
          </h3>
        </header>
        <div class="grid grid-cols-2 gap-2">
          <.canvas_field field="width" label={gettext("Width")} value={@scene.canvas.width} />
          <.canvas_field field="height" label={gettext("Height")} value={@scene.canvas.height} />
        </div>
        <p class="text-xs text-base-content/50">
          {gettext("OpenGraph consumers expect 1200×630. Custom sizes render fine.")}
        </p>
      </section>

      <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
        <header class="flex items-center gap-1.5">
          <.icon name="hero-paint-brush" class="w-3.5 h-3.5 text-base-content/50" />
          <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
            {gettext("Background")}
          </h3>
        </header>

        <form phx-change="update_canvas" class="tabs tabs-boxed bg-base-200 p-0.5">
          <input type="hidden" name="field" value="bg_type" />
          <label class={"tab tab-sm flex-1 #{@bg_type == :solid && "tab-active"}"}>
            <input type="radio" name="value" value="solid" checked={@bg_type == :solid} class="sr-only" />
            {gettext("Color")}
          </label>
          <label class={"tab tab-sm flex-1 #{@bg_type == :image && "tab-active"}"}>
            <input type="radio" name="value" value="image" checked={@bg_type == :image} class="sr-only" />
            {gettext("Image")}
          </label>
          <label class={"tab tab-sm flex-1 #{@bg_type == :gradient && "tab-active"}"}>
            <input
              type="radio"
              name="value"
              value="gradient"
              checked={@bg_type == :gradient}
              class="sr-only"
            />
            {gettext("Gradient")}
          </label>
        </form>

        <%= case @bg_type do %>
          <% :solid -> %>
            <.canvas_color_field
              field="bg_color"
              label={gettext("Color")}
              value={Map.get(@bg, :color, "#0b1220")}
            />
          <% :image -> %>
            <.image_value_controls
              value={Map.get(@bg, :value)}
              media_target="background_value"
              variable_field="bg_image_variable_name"
              form_event="update_canvas"
            />
            <div>
              <label class="label py-0.5">
                <span class="label-text text-xs">{gettext("Fit")}</span>
              </label>
              <% fit = Map.get(@bg, :fit, :cover) %>
              <form phx-change="update_canvas" class="tabs tabs-boxed bg-base-200 p-0.5">
                <input type="hidden" name="field" value="bg_image_fit" />
                <label
                  :for={{v, l} <- [{"cover", gettext("Fill")}, {"contain", gettext("Contain")}, {"stretch", gettext("Stretch")}]}
                  class={"tab tab-sm flex-1 #{to_string(fit) == v && "tab-active"}"}
                >
                  <input type="radio" name="value" value={v} checked={to_string(fit) == v} class="sr-only" />
                  {l}
                </label>
              </form>
            </div>
          <% :gradient -> %>
            <.gradient_controls gradient={@bg} />
        <% end %>
      </section>

      <p class="text-xs text-base-content/50 pt-1">
        {gettext("Changes autosave 800ms after each edit. Ctrl+S saves immediately.")}
      </p>
    </div>
    """
  end

  attr(:gradient, :map, required: true)

  defp gradient_controls(assigns) do
    stops = Map.get(assigns.gradient, :stops, [])
    from = Enum.at(stops, 0, %{color: "#0b1220"})
    to = Enum.at(stops, 1, %{color: "#2563eb"})

    assigns =
      assigns
      |> assign(:angle, Map.get(assigns.gradient, :angle, 180))
      |> assign(:from_color, Map.get(from, :color, "#0b1220"))
      |> assign(:to_color, Map.get(to, :color, "#2563eb"))

    ~H"""
    <div class="space-y-2">
      <.canvas_color_field field="bg_gradient_from" label={gettext("From")} value={@from_color} />
      <.canvas_color_field field="bg_gradient_to" label={gettext("To")} value={@to_color} />
      <div>
        <label class="label py-0.5 flex items-center justify-between">
          <span class="label-text text-xs">{gettext("Angle")}</span>
          <span class="text-xs text-base-content/50">{@angle}°</span>
        </label>
        <form phx-change="update_canvas">
          <input type="hidden" name="field" value="bg_gradient_angle" />
          <input
            type="range"
            name="value"
            min="0"
            max="360"
            step="15"
            value={@angle}
            class="range range-xs w-full"
          />
        </form>
      </div>
    </div>
    """
  end

  # Shared Constant/Variable controls for an image value (element src or
  # background image fill): Constant mode = media picker; Variable mode
  # = a `{{name}}` slot input.
  attr(:value, :any, required: true)
  attr(:media_target, :string, required: true)
  attr(:variable_field, :string, required: true)
  attr(:form_event, :string, required: true)
  attr(:el_id, :string, default: nil)

  defp image_value_controls(assigns) do
    {mode, literal, var_name} =
      case assigns.value do
        %{placeholder: name} -> {"variable", "", name}
        v when is_binary(v) -> {"constant", v, ""}
        _ -> {"constant", "", ""}
      end

    assigns =
      assigns
      |> assign(:mode, mode)
      |> assign(:literal, literal)
      |> assign(:var_name, var_name)

    ~H"""
    <div class="space-y-2">
      <div>
        <label class="label py-0.5">
          <span class="label-text text-xs">{gettext("Source")}</span>
        </label>
        <div class="tabs tabs-boxed bg-base-200 p-0.5">
          <button
            type="button"
            phx-click={mode_event(@el_id, "constant")}
            class={["tab tab-sm flex-1", @mode == "constant" && "tab-active"]}
          >
            {gettext("Constant")}
          </button>
          <button
            type="button"
            phx-click={mode_event(@el_id, "variable")}
            class={["tab tab-sm flex-1", @mode == "variable" && "tab-active"]}
          >
            {gettext("Variable")}
          </button>
        </div>
      </div>

      <%= if @mode == "constant" do %>
        <.media_field target={@media_target} value={@literal} label={gettext("Image")} />
      <% else %>
        <div>
          <label class="label py-0.5">
            <span class="label-text text-xs">{gettext("Variable name")}</span>
          </label>
          <form phx-change={@form_event} class="flex items-center gap-2">
            <input :if={@el_id} type="hidden" name="el_id" value={@el_id} />
            <input type="hidden" name="field" value={@variable_field} />
            <span class="text-xs text-base-content/50 font-mono"><%= "{{" %></span>
            <input
              type="text"
              name="value"
              value={@var_name}
              placeholder="Image"
              class="input input-bordered input-sm flex-1 font-mono text-xs"
            />
            <span class="text-xs text-base-content/50 font-mono"><%= "}}" %></span>
          </form>
          <p class="text-xs text-base-content/50 mt-1">
            {gettext("Shows up on the Assignments page — pick which module variable it maps to.")}
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # Background image mode switches ride update_canvas; element image
  # mode switches ride set_image_mode (which seeds fresh slot names).
  defp mode_event(nil, mode) do
    JS.push("update_canvas",
      value: %{field: "bg_image_variable_name", value: bg_mode_seed(mode)}
    )
  end

  defp mode_event(el_id, mode) do
    JS.push("set_image_mode", value: %{el_id: el_id, mode: mode})
  end

  defp bg_mode_seed("variable"), do: "BackgroundImage"
  defp bg_mode_seed(_), do: ""

  # ==============================================================
  # Property panel — selected element
  # ==============================================================
  attr(:selected, :map, required: true)
  attr(:scene, :map, required: true)

  defp property_panel(assigns) do
    el = assigns.selected

    assigns =
      assigns
      |> assign(:el, el)
      |> assign(:type, Map.get(el, :type, :text))

    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold text-base">{type_label(@type)}</h2>
        <button type="button" phx-click="deselect" class="btn btn-ghost btn-xs">
          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
        </button>
      </div>

      <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
        <header class="flex items-center gap-1.5">
          <.icon name="hero-arrows-pointing-out" class="w-3.5 h-3.5 text-base-content/50" />
          <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
            {gettext("Position & size")}
          </h3>
        </header>
        <div class="grid grid-cols-2 gap-2">
          <.prop_number el_id={@el.id} field="x" label="X" value={@el.box.x} />
          <.prop_number el_id={@el.id} field="y" label="Y" value={@el.box.y} />
          <.prop_number el_id={@el.id} field="w" label={gettext("Width")} value={@el.box.w} />
          <.prop_number el_id={@el.id} field="h" label={gettext("Height")} value={@el.box.h} />
        </div>
        <.anchor_controls el={@el} scene={@scene} />
      </section>

      <%= case @type do %>
        <% t when t in [:text, :stamp] -> %>
          <.text_props el={@el} />
        <% :image -> %>
          <.image_props el={@el} />
        <% :shape -> %>
          <.shape_props el={@el} />
        <% :button -> %>
          <.button_props el={@el} />
        <% _ -> %>
          <p class="text-xs text-base-content/50">{gettext("No editable properties.")}</p>
      <% end %>
    </div>
    """
  end

  defp type_label(:text), do: gettext("Text")
  defp type_label(:stamp), do: gettext("Stamp")
  defp type_label(:image), do: gettext("Image")
  defp type_label(:shape), do: gettext("Rectangle")
  defp type_label(:button), do: gettext("Button")
  defp type_label(other), do: to_string(other)

  # Anchor: pin this element below/above another so it follows the
  # target's rendered height (e.g. a CTA under a wrapping title).
  attr(:el, :map, required: true)
  attr(:scene, :map, required: true)

  defp anchor_controls(assigns) do
    anchor = Map.get(assigns.el, :anchor)

    targets =
      assigns.scene.elements
      |> Enum.reject(&(&1.id == assigns.el.id))
      |> Enum.map(& &1.id)

    assigns =
      assigns
      |> assign(:anchor, anchor)
      |> assign(:targets, targets)

    ~H"""
    <div class="pt-2 border-t border-base-300/60 space-y-2">
      <label class="label py-0.5">
        <span class="label-text text-xs">
          {gettext("Anchor to")}
          <span
            class="text-base-content/40 cursor-help"
            title={
              gettext(
                "Pins this element relative to another one. When the target grows (a title wrapping to two lines), this element moves with it."
              )
            }
          >
            ?
          </span>
        </span>
      </label>
      <form phx-change="update_prop">
        <input type="hidden" name="el_id" value={@el.id} />
        <input type="hidden" name="field" value="anchor_to" />
        <label class="select select-bordered select-sm w-full">
          <select name="value">
            <option value="" selected={is_nil(@anchor)}>{gettext("Nothing (fixed position)")}</option>
            <option :for={t <- @targets} value={t} selected={@anchor && @anchor.to == t}>
              {t}
            </option>
          </select>
        </label>
      </form>

      <div :if={@anchor} class="grid grid-cols-2 gap-2">
        <div>
          <form phx-change="update_prop" class="tabs tabs-boxed bg-base-200 p-0.5">
            <input type="hidden" name="el_id" value={@el.id} />
            <input type="hidden" name="field" value="anchor_edge" />
            <label class={"tab tab-sm flex-1 #{@anchor.edge == :below && "tab-active"}"}>
              <input type="radio" name="value" value="below" checked={@anchor.edge == :below} class="sr-only" />
              {gettext("Below")}
            </label>
            <label class={"tab tab-sm flex-1 #{@anchor.edge == :above && "tab-active"}"}>
              <input type="radio" name="value" value="above" checked={@anchor.edge == :above} class="sr-only" />
              {gettext("Above")}
            </label>
          </form>
        </div>
        <.prop_number el_id={@el.id} field="anchor_gap" label={gettext("Gap")} value={@anchor.gap} />
      </div>
    </div>
    """
  end

  attr(:el, :map, required: true)

  defp text_props(assigns) do
    {mode, literal, var_name} =
      case assigns.el.value do
        %{placeholder: name} -> {"variable", "", name}
        v when is_binary(v) -> {"constant", v, ""}
        _ -> {"constant", "", ""}
      end

    assigns =
      assigns
      |> assign(:mode, mode)
      |> assign(:literal, literal)
      |> assign(:var_name, var_name)

    ~H"""
    <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
      <header class="flex items-center gap-1.5">
        <.icon name="hero-bars-3-bottom-left" class="w-3.5 h-3.5 text-base-content/50" />
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
          {gettext("Content")}
        </h3>
      </header>

      <%= if @mode == "variable" do %>
        <div>
          <label class="label py-0.5">
            <span class="label-text text-xs">{gettext("Variable name")}</span>
          </label>
          <form phx-change="update_prop_variable" class="flex items-center gap-2">
            <input type="hidden" name="el_id" value={@el.id} />
            <input type="hidden" name="field" value="value" />
            <span class="text-xs text-base-content/50 font-mono"><%= "{{" %></span>
            <input
              type="text"
              name="value"
              value={@var_name}
              class="input input-bordered input-sm flex-1 font-mono text-xs"
            />
            <span class="text-xs text-base-content/50 font-mono"><%= "}}" %></span>
          </form>
        </div>
      <% else %>
        <form phx-change="update_prop">
          <input type="hidden" name="el_id" value={@el.id} />
          <input type="hidden" name="field" value="value" />
          <textarea
            name="value"
            rows="3"
            class="textarea textarea-bordered textarea-sm w-full"
            placeholder={gettext(~S|Text — inline {{slots}} and [[globals]] work too|)}
          ><%= @literal %></textarea>
        </form>
      <% end %>

      <div class="grid grid-cols-2 gap-2">
        <.prop_number el_id={@el.id} field="size" label={gettext("Size")} value={@el.size} />
        <.prop_number el_id={@el.id} field="weight" label={gettext("Weight")} value={@el.weight} />
      </div>
      <.prop_color el_id={@el.id} field="color" label={gettext("Color")} value={fill_color(@el)} />

      <div>
        <label class="label py-0.5">
          <span class="label-text text-xs">{gettext("Align")}</span>
        </label>
        <form phx-change="update_prop" class="tabs tabs-boxed bg-base-200 p-0.5">
          <input type="hidden" name="el_id" value={@el.id} />
          <input type="hidden" name="field" value="align" />
          <label
            :for={{v, l} <- [{"left", gettext("Left")}, {"center", gettext("Center")}, {"right", gettext("Right")}]}
            class={"tab tab-sm flex-1 #{to_string(@el.align) == v && "tab-active"}"}
          >
            <input type="radio" name="value" value={v} checked={to_string(@el.align) == v} class="sr-only" />
            {l}
          </label>
        </form>
      </div>

      <.underlay_controls el={@el} />
    </section>
    """
  end

  attr(:el, :map, required: true)

  defp image_props(assigns) do
    ~H"""
    <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
      <header class="flex items-center gap-1.5">
        <.icon name="hero-photo" class="w-3.5 h-3.5 text-base-content/50" />
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
          {gettext("Image")}
        </h3>
      </header>

      <.image_value_controls
        value={@el.value}
        media_target="element_src"
        variable_field="value"
        form_event="update_prop_variable"
        el_id={@el.id}
      />

      <div>
        <label class="label py-0.5">
          <span class="label-text text-xs">{gettext("Fit")}</span>
        </label>
        <form phx-change="update_prop" class="tabs tabs-boxed bg-base-200 p-0.5">
          <input type="hidden" name="el_id" value={@el.id} />
          <input type="hidden" name="field" value="fit" />
          <label
            :for={{v, l} <- [{"cover", gettext("Fill")}, {"contain", gettext("Contain")}, {"stretch", gettext("Stretch")}]}
            class={"tab tab-sm flex-1 #{to_string(@el.fit) == v && "tab-active"}"}
          >
            <input type="radio" name="value" value={v} checked={to_string(@el.fit) == v} class="sr-only" />
            {l}
          </label>
        </form>
      </div>

      <.prop_number el_id={@el.id} field="radius" label={gettext("Corner radius")} value={@el.radius} />
    </section>
    """
  end

  attr(:el, :map, required: true)

  defp shape_props(assigns) do
    ~H"""
    <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
      <header class="flex items-center gap-1.5">
        <.icon name="hero-rectangle-group" class="w-3.5 h-3.5 text-base-content/50" />
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
          {gettext("Rectangle")}
        </h3>
      </header>
      <.prop_color el_id={@el.id} field="color" label={gettext("Fill")} value={fill_color(@el)} />
      <.prop_number el_id={@el.id} field="radius" label={gettext("Corner radius")} value={Map.get(@el, :radius, 0)} />
    </section>
    """
  end

  attr(:el, :map, required: true)

  defp button_props(assigns) do
    {label_mode, label_literal, label_var} =
      case assigns.el.label do
        %{placeholder: name} -> {"variable", "", name}
        v when is_binary(v) -> {"constant", v, ""}
        _ -> {"constant", "", ""}
      end

    assigns =
      assigns
      |> assign(:label_mode, label_mode)
      |> assign(:label_literal, label_literal)
      |> assign(:label_var, label_var)

    ~H"""
    <section class="rounded-lg border border-base-300/70 bg-base-200/30 p-3 space-y-2">
      <header class="flex items-center gap-1.5">
        <.icon name="hero-cursor-arrow-ripple" class="w-3.5 h-3.5 text-base-content/50" />
        <h3 class="text-xs font-semibold text-base-content/70 uppercase tracking-wide">
          {gettext("Button")}
        </h3>
      </header>

      <%= if @label_mode == "variable" do %>
        <div>
          <label class="label py-0.5">
            <span class="label-text text-xs">
              {gettext("Label variable (translatable per post language)")}
            </span>
          </label>
          <form phx-change="update_prop_variable" class="flex items-center gap-2">
            <input type="hidden" name="el_id" value={@el.id} />
            <input type="hidden" name="field" value="label" />
            <span class="text-xs text-base-content/50 font-mono"><%= "{{" %></span>
            <input
              type="text"
              name="value"
              value={@label_var}
              class="input input-bordered input-sm flex-1 font-mono text-xs"
            />
            <span class="text-xs text-base-content/50 font-mono"><%= "}}" %></span>
          </form>
        </div>
      <% else %>
        <div>
          <label class="label py-0.5">
            <span class="label-text text-xs">{gettext("Label")}</span>
          </label>
          <form phx-change="update_prop">
            <input type="hidden" name="el_id" value={@el.id} />
            <input type="hidden" name="field" value="label" />
            <input
              type="text"
              name="value"
              value={@label_literal}
              class="input input-bordered input-sm w-full"
              placeholder={gettext(~S|Label — or type {{cta}} to make it a slot|)}
            />
          </form>
        </div>
      <% end %>

      <div>
        <label class="label py-0.5">
          <span class="label-text text-xs">{gettext("Style")}</span>
        </label>
        <form phx-change="update_prop" class="tabs tabs-boxed bg-base-200 p-0.5">
          <input type="hidden" name="el_id" value={@el.id} />
          <input type="hidden" name="field" value="preset" />
          <label
            :for={{v, l} <- [{"solid", gettext("Solid")}, {"outline", gettext("Outline")}, {"soft", gettext("Soft")}]}
            class={"tab tab-sm flex-1 #{to_string(Map.get(@el, :preset, :solid)) == v && "tab-active"}"}
          >
            <input
              type="radio"
              name="value"
              value={v}
              checked={to_string(Map.get(@el, :preset, :solid)) == v}
              class="sr-only"
            />
            {l}
          </label>
        </form>
      </div>

      <div class="grid grid-cols-2 gap-2">
        <.prop_color el_id={@el.id} field="color" label={gettext("Fill")} value={fill_color(@el)} />
        <.prop_color
          el_id={@el.id}
          field="text_color"
          label={gettext("Text")}
          value={text_fill_color(@el)}
        />
      </div>

      <div class="grid grid-cols-2 gap-2">
        <.prop_number el_id={@el.id} field="size" label={gettext("Text size")} value={@el.size} />
        <.prop_number el_id={@el.id} field="radius" label={gettext("Radius")} value={@el.radius} />
      </div>

      <label class="label cursor-pointer justify-start gap-2 py-1">
        <form phx-change="update_prop">
          <input type="hidden" name="el_id" value={@el.id} />
          <input type="hidden" name="field" value="auto_width" />
          <input
            type="checkbox"
            name="value"
            value="true"
            checked={Map.get(@el, :auto_width, false)}
            class="checkbox checkbox-sm"
          />
        </form>
        <span class="label-text text-xs">
          {gettext("Auto-width (grows with the label — recommended for translated labels)")}
        </span>
      </label>
    </section>
    """
  end

  attr(:el, :map, required: true)

  defp underlay_controls(assigns) do
    ~H"""
    <div class="pt-2 border-t border-base-300/60 space-y-2">
      <label class="label py-0.5 flex items-center justify-between">
        <span class="label-text text-xs">{gettext("Legibility underlay")}</span>
        <span class="text-xs text-base-content/50">
          {round(Map.get(@el, :underlay_opacity, 0) * 100)}%
        </span>
      </label>
      <form phx-change="update_prop">
        <input type="hidden" name="el_id" value={@el.id} />
        <input type="hidden" name="field" value="underlay_opacity" />
        <input
          type="range"
          name="value"
          min="0"
          max="1"
          step="0.05"
          value={Map.get(@el, :underlay_opacity, 0)}
          class="range range-xs w-full"
        />
      </form>
    </div>
    """
  end

  # =========================================================================
  # Small field components
  # =========================================================================

  attr(:el_id, :string, required: true)
  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp prop_number(assigns) do
    ~H"""
    <div>
      <label class="label py-0.5">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <form phx-change="update_prop">
        <input type="hidden" name="el_id" value={@el_id} />
        <input type="hidden" name="field" value={@field} />
        <input
          type="number"
          name="value"
          value={round_num(@value)}
          step="1"
          class="input input-bordered input-sm w-full"
        />
      </form>
    </div>
    """
  end

  attr(:el_id, :string, required: true)
  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp prop_color(assigns) do
    ~H"""
    <div>
      <label class="label py-0.5">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <form phx-change="update_prop" class="flex items-center gap-2">
        <input type="hidden" name="el_id" value={@el_id} />
        <input type="hidden" name="field" value={@field} />
        <input
          type="color"
          name="value"
          value={normalize_color(@value)}
          oninput="this.nextElementSibling.value = this.value"
          class="w-10 h-8 rounded border border-base-300"
        />
        <input
          type="text"
          name="value"
          value={@value}
          oninput="this.previousElementSibling.value = this.value"
          class="input input-bordered input-sm flex-1 font-mono text-xs"
        />
      </form>
    </div>
    """
  end

  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp canvas_field(assigns) do
    ~H"""
    <div>
      <label class="label py-0.5">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <form phx-change="update_canvas">
        <input type="hidden" name="field" value={@field} />
        <input
          type="number"
          name="value"
          value={@value}
          step="1"
          class="input input-bordered input-sm w-full"
        />
      </form>
    </div>
    """
  end

  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp canvas_color_field(assigns) do
    ~H"""
    <div>
      <label class="label py-0.5">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <form phx-change="update_canvas" class="flex items-center gap-2">
        <input type="hidden" name="field" value={@field} />
        <input
          type="color"
          name="value"
          value={normalize_color(@value)}
          oninput="this.nextElementSibling.value = this.value"
          class="w-10 h-8 rounded border border-base-300"
        />
        <input
          type="text"
          name="value"
          value={@value}
          oninput="this.previousElementSibling.value = this.value"
          class="input input-bordered input-sm flex-1 font-mono text-xs"
        />
      </form>
    </div>
    """
  end

  attr(:target, :string, required: true)
  attr(:value, :any, required: true)
  attr(:label, :string, required: true)

  defp media_field(assigns) do
    preview = media_preview_url(assigns.value)
    assigns = assign(assigns, :preview, preview)

    ~H"""
    <div class="space-y-2">
      <label class="label py-0.5">
        <span class="label-text text-xs">{@label}</span>
      </label>
      <%= if @preview do %>
        <img
          src={@preview}
          alt={@label}
          class="w-full rounded-lg border-2 border-base-300 object-cover max-h-40"
          loading="lazy"
        />
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="open_media_picker"
            phx-value-target={@target}
            class="btn btn-outline btn-xs flex-1"
          >
            <.icon name="hero-arrow-path" class="w-3 h-3 mr-1" />
            {gettext("Change")}
          </button>
          <button
            type="button"
            phx-click="clear_media_field"
            phx-value-target={@target}
            class="btn btn-outline btn-error btn-xs flex-1"
          >
            <.icon name="hero-trash" class="w-3 h-3 mr-1" />
            {gettext("Remove")}
          </button>
        </div>
      <% else %>
        <button
          type="button"
          phx-click="open_media_picker"
          phx-value-target={@target}
          class="btn btn-outline btn-sm w-full"
        >
          <.icon name="hero-photo" class="w-4 h-4 mr-1" />
          {gettext("Choose image")}
        </button>
      <% end %>
    </div>
    """
  end

  # Resolves a media-uuid or URL into a preview URL for the small
  # thumbnail. Empty strings show no preview.
  defp media_preview_url(nil), do: nil
  defp media_preview_url(""), do: nil
  defp media_preview_url("http://" <> _ = url), do: url
  defp media_preview_url("https://" <> _ = url), do: url
  defp media_preview_url("/" <> _ = url), do: url
  defp media_preview_url("data:" <> _ = url), do: url

  defp media_preview_url(uuid) when is_binary(uuid) do
    PhoenixKit.Modules.Storage.get_public_url_by_uuid(uuid, "medium") ||
      PhoenixKit.Modules.Storage.get_public_url_by_uuid(uuid)
  rescue
    _ -> nil
  end

  defp media_preview_url(_), do: nil

  defp fill_color(%{fill: %{type: :solid, color: color}}), do: color
  defp fill_color(_), do: "#ffffff"

  defp text_fill_color(%{text_fill: %{type: :solid, color: color}}), do: color
  defp text_fill_color(_), do: "#ffffff"

  defp round_num(n) when is_float(n), do: round(n)
  defp round_num(n), do: n

  # The color input needs a #rrggbb value; pass anything else through
  # as a neutral so the picker doesn't reject it.
  defp normalize_color("#" <> _ = color) when byte_size(color) == 7, do: color
  defp normalize_color(_), do: "#000000"
end
