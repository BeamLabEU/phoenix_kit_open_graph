defmodule PhoenixKitOG.Test.Endpoint do
  @moduledoc """
  Minimal Phoenix.Endpoint used by the LiveView test suite.

  `phoenix_kit_og` is a library — in production it borrows the host app's
  endpoint and router. For tests we spin up a tiny endpoint + router
  (`PhoenixKitOG.Test.Router`) so `Phoenix.LiveViewTest` can drive our
  LiveViews through `live/2` with real URLs. Same recipe as
  `phoenix_kit_entities` / `phoenix_kit_publishing`.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_kit_og

  @session_options [
    store: :cookie,
    key: "_phoenix_kit_og_test_key",
    signing_salt: "og-test-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(PhoenixKitOG.Test.Router)
end
