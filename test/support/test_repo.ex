defmodule PhoenixKitOG.Test.Repo do
  @moduledoc "Test-only Ecto repo. Configured in config/test.exs, started by test_helper.exs."
  use Ecto.Repo, otp_app: :phoenix_kit_og, adapter: Ecto.Adapters.Postgres
end
