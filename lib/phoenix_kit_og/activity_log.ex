defmodule PhoenixKitOG.ActivityLog do
  @moduledoc """
  Thin wrapper around `PhoenixKit.Activity.log/3` for the OG plugin.

  Every entry is stamped with `module: "phoenix_kit_og"` so the admin
  activity feed can filter to just this plugin's events. Callers pass
  the pipe-friendly `{:ok, struct}` shape so the return value chains
  cleanly through context functions. Core never raises — a missing
  activities table on a fresh host, or any other failure, is logged
  there and returned — so logging never breaks the mutation.

  Metadata is PII-safe by convention: names, statuses, counts, UUIDs
  are OK; email / phone / free-text / anything a user could paste in
  is not.
  """

  @module_key "phoenix_kit_og"

  @doc """
  Pipe step for context functions returning `{:ok, struct}`. Logs the
  action and returns the value unchanged. `{:error, _}` short-circuits
  to a no-op so callers can put this at the tail of the pipe.

  ## Example

      %Template{}
      |> Template.changeset(attrs)
      |> Repo.insert()
      |> ActivityLog.log("template.created", opts, &template_activity_fields/1)
  """
  @spec log(
          {:ok, struct()} | {:error, term()},
          String.t(),
          keyword(),
          (struct() -> map())
        ) :: {:ok, struct()} | {:error, term()}
  def log({:ok, struct} = ok, action, opts, fields_fn)
      when is_binary(action) and is_function(fields_fn, 1) do
    maybe_log(action, opts, fields_fn.(struct))
    ok
  end

  # Audit the ATTEMPT even on failure: the user initiated the action, so
  # the trail shouldn't lose it because a changeset was invalid. For an
  # UPDATE/DELETE the changeset's `data` carries the loaded struct (with
  # its uuid), so run `fields_fn` on it to preserve the resource context
  # — a failed edit points at WHICH record it targeted. A failed CREATE's
  # `data` is a blank struct (uuid nil), which resolves to no resource_uuid,
  # exactly right.
  def log({:error, %Ecto.Changeset{data: data} = cs} = err, action, opts, fields_fn)
      when is_binary(action) and is_function(fields_fn, 1) do
    fields =
      data
      |> fields_fn.()
      |> Map.update(:metadata, %{"failed" => true, "reason" => "validation"}, fn m ->
        Map.merge(m, %{"failed" => true, "reason" => failure_reason(cs)})
      end)

    log_failed(action, opts, fields)
    err
  end

  # Non-changeset error (e.g. an atom reason) — no struct to key off, so
  # just record the flagged attempt.
  def log({:error, reason} = err, action, opts, _fields_fn) when is_binary(action) do
    log_failed(action, opts, %{
      metadata: %{"failed" => true, "reason" => failure_reason(reason)}
    })

    err
  end

  defp failure_reason(%Ecto.Changeset{}), do: "validation"
  defp failure_reason(reason) when is_atom(reason), do: to_string(reason)
  defp failure_reason(_), do: "error"

  @doc """
  Log without the pipe wrapper — for transactions, toggles, and other
  paths where the caller doesn't have a `{:ok, struct}` in hand.
  """
  @spec maybe_log(String.t(), keyword(), map()) :: :ok
  def maybe_log(action, opts, fields) when is_binary(action) and is_map(fields) do
    PhoenixKit.Activity.log(@module_key, action, core_opts(opts, fields))
    :ok
  end

  # A write that did not land goes through core's `log_failed/3`: it stamps
  # `"db_pending" => true`, so the core feed can tell an attempt from an
  # action, and it never fans out a notification. Our own `failed` /
  # `reason` keys ride along for this module's readers.
  defp log_failed(action, opts, fields) do
    PhoenixKit.Activity.log_failed(@module_key, action, core_opts(opts, fields))
    :ok
  end

  defp core_opts(opts, fields) do
    [
      mode: Keyword.get(opts, :mode, "manual"),
      actor_uuid: Keyword.get(opts, :actor_uuid),
      resource_type: Map.get(fields, :resource_type),
      resource_uuid: Map.get(fields, :resource_uuid),
      metadata: Map.get(fields, :metadata)
    ]
  end
end
