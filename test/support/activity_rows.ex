defmodule PhoenixKitOG.ActivityRows do
  @moduledoc """
  Reads `phoenix_kit_activities` for assertions: the rows of one action as
  maps with string uuids, so a test can pin the actor, the resource and
  the row COUNT of what a mutation logged.
  """

  import Ecto.Query

  alias PhoenixKitOG.Test.Repo

  @doc "Every activity row with `action`, oldest first."
  def rows(action) do
    from(a in "phoenix_kit_activities",
      where: a.action == ^action,
      order_by: [asc: a.inserted_at],
      select: %{
        action: a.action,
        mode: a.mode,
        actor_uuid: a.actor_uuid,
        resource_type: a.resource_type,
        resource_uuid: a.resource_uuid,
        metadata: a.metadata
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | actor_uuid: uuid(row.actor_uuid), resource_uuid: uuid(row.resource_uuid)}
    end)
  end

  defp uuid(<<_::128>> = raw), do: Ecto.UUID.load!(raw)
  defp uuid(other), do: other
end
