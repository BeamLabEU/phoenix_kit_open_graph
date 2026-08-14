defmodule PhoenixKitOG.Test.Router do
  @moduledoc """
  Minimal Router for the LiveView test suite. Routes match the URLs the OG
  admin LiveViews are mounted at in production (`/admin/open-graph` and
  `.../assignments`, with the default "en" locale prefix) so `live/2` calls
  work with a production-ish URL shape.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {PhoenixKitOG.Test.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/en/admin/open-graph", PhoenixKitOG.Web do
    pipe_through(:browser)

    live_session :og_test,
      layout: {PhoenixKitOG.Test.Layouts, :app},
      on_mount: {PhoenixKitOG.Test.Hooks, :assign_scope} do
      live("/", TemplatesLive, :index, as: :og_templates)
      live("/assignments", AssignmentsLive, :index, as: :og_assignments)
    end
  end
end
