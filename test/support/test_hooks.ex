defmodule PhoenixKitOG.Test.Hooks do
  @moduledoc """
  `on_mount` hooks for the LiveView test endpoint.

  Production runs these LiveViews inside core's admin `live_session`, which
  populates `socket.assigns[:phoenix_kit_current_scope]` and
  `[:phoenix_kit_current_user]` from the host app's authentication. The test
  endpoint doesn't load core's hooks, so this replicates the effect by
  pulling scope data from the test session — set via
  `PhoenixKitOG.LiveCase.put_test_scope/2`.

  Also seeds `:current_locale` / `:url_path` so LVs that read them don't
  crash on a missing assign.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:assign_scope, _params, session, socket) do
    socket =
      socket
      |> assign(:current_locale, session["phoenix_kit_test_locale"] || "en-US")
      |> assign(:url_path, "/en/admin/open-graph")

    socket =
      case Map.get(session, "phoenix_kit_test_scope") do
        nil ->
          socket

        %{user: user} = scope ->
          socket
          |> assign(:phoenix_kit_current_scope, scope)
          |> assign(:phoenix_kit_current_user, user)
      end

    {:cont, socket}
  end
end
