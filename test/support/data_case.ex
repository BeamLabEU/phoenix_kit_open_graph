defmodule PhoenixKitOG.DataCase do
  @moduledoc """
  Test case for tests needing DB access. Auto-tagged `:integration` so they're
  excluded when Postgres or the OG tables are unavailable (see test_helper.exs).

  The OG tables (`phoenix_kit_og_templates` / `_assignments`) are built by this
  module's own chain in test_helper.exs (core 3.x creates none).
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      alias PhoenixKitOG.Test.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitOG.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
