# Add the compiled test/support ebin to the code path (needed when `mix test`
# runs outside :test env in this repo layout).
test_support_ebin =
  Path.join([File.cwd!(), "_build", "test", "lib", "phoenix_kit_og", "ebin"])

if File.dir?(test_support_ebin), do: :code.add_patha(to_charlist(test_support_ebin))

alias PhoenixKitOG.Test.Repo, as: TestRepo

db_config = Application.get_env(:phoenix_kit_og, TestRepo, [])
db_name = db_config[:database] || "phoenix_kit_og_test"

# The preflight ships in core, and this module's core floor (`~> 2.0`)
# predates it — so it is used when the running core has it, and otherwise
# this falls through to exactly the previous behaviour.
db_check =
  if Code.ensure_loaded?(PhoenixKit.TestSupport.PostgresPreflight) do
    # One classified connection attempt, with the repo's OWN credentials and
    # transport, before anything starts the pool.
    #
    # This replaces a `psql -lqt` listing. That check asked the wrong question:
    # it ran as the shell's user over a unix socket, so it reported "the
    # database is there" and said nothing about whether the CONFIGURED role
    # could reach it over TCP. When it could not, the answer arrived minutes
    # later as a pool checkout timeout that reads like a flaky test.
    case PhoenixKit.TestSupport.PostgresPreflight.check(db_config) do
      :ok ->
        :exists

      {:error, _reason, message} ->
        IO.puts(:stderr, "\n" <> message)
        :not_found
    end
  else
    :try_connect
  end

repo_available =
  if db_check == :not_found do
    IO.puts(
      "\n  Cannot reach test database \"#{db_name}\" — integration tests excluded.\n     The reason is printed above.\n"
    )

    false
  else
    try do
      {:ok, _} = TestRepo.start_link()
      TestRepo.query!("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

      TestRepo.query!("""
      CREATE OR REPLACE FUNCTION uuid_generate_v7()
      RETURNS uuid AS $$
      DECLARE
        unix_ts_ms bytea;
        uuid_bytes bytea;
      BEGIN
        unix_ts_ms := substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3);
        uuid_bytes := unix_ts_ms || gen_random_bytes(10);
        uuid_bytes := set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112);
        uuid_bytes := set_byte(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128);
        RETURN encode(uuid_bytes, 'hex')::uuid;
      END;
      $$ LANGUAGE plpgsql VOLATILE;
      """)

      # Apply core's versioned migration chain (which includes the OG tables at
      # V154) so the integration suite has a schema.
      PhoenixKit.Migration.ensure_current(TestRepo, log: false)

      # The OG tables ship in core V154. Without PHOENIX_KIT_PATH the suite
      # resolves the *published* core (~> 1.7.189, pre-V154) — so integration
      # tests get excluded (with a hint) instead of failing on a missing table.
      %{rows: [[og_tables?]]} =
        TestRepo.query!(
          "SELECT EXISTS (SELECT 1 FROM information_schema.tables " <>
            "WHERE table_name = 'phoenix_kit_og_templates')"
        )

      # Also run this module's OWN adoption chain (PhoenixKitOG.Migrations)
      # against the real database, so the integration suite exercises V1's
      # guarded DDL for real on every run — not just as parsed text in
      # migrations_test.exs. A no-op against the shape core's V154 already
      # created; it just stamps the pkog_schema:1 marker.
      if og_tables? do
        PhoenixKitOG.Migrations.up_statements("public", 1)
        |> Enum.each(&TestRepo.query!(&1))
      end

      Application.put_env(:phoenix_kit_og, :og_tables_present, og_tables?)

      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
      true
    rescue
      e ->
        IO.puts(
          "\n  Could not connect to test database — integration tests excluded.\n     Error: #{Exception.message(e)}\n"
        )

        false
    catch
      :exit, reason ->
        IO.puts(
          "\n  Could not connect to test database — integration tests excluded.\n     Error: #{inspect(reason)}\n"
        )

        false
    end
  end

og_tables_present =
  repo_available and Application.get_env(:phoenix_kit_og, :og_tables_present, false)

if repo_available and not og_tables_present do
  IO.puts("""
  \n  Resolved core has no OG tables (its V154 migration isn't applied) —
     integration tests excluded. Run against local core:
       PHOENIX_KIT_PATH=../phoenix_kit mix test
  """)
end

if Code.ensure_loaded?(PhoenixKit.PubSub.Manager), do: PhoenixKit.PubSub.Manager.start_link([])
if Code.ensure_loaded?(PhoenixKit.ModuleRegistry), do: PhoenixKit.ModuleRegistry.start_link([])

# Start the test endpoint so Phoenix.LiveViewTest can drive the admin LVs.
# Needs the repo: every LV loads from the DB at mount, so LiveCase tests are
# `:integration`-tagged and excluded together with the rest when it's absent.
if repo_available and og_tables_present do
  {:ok, _pid} = PhoenixKitOG.Test.Endpoint.start_link()
end

:persistent_term.put({PhoenixKit.Config, :url_prefix}, "/")

# Quiet expected "Failed to query setting …" OwnershipError noise: background
# processes occasionally query settings without a sandbox connection. Core
# returns the default; it's log spam, not a failure.
:logger.add_primary_filter(
  :phoenix_kit_og_drop_settings_noise,
  {fn log_event, _extra ->
     msg =
       case log_event do
         %{msg: {:string, m}} ->
           IO.iodata_to_binary(m)

         %{msg: {fmt, args}} when is_list(fmt) ->
           fmt |> :io_lib.format(args) |> IO.iodata_to_binary()

         _ ->
           ""
       end

     if String.contains?(msg, "Failed to query"), do: :stop, else: :ignore
   end, []}
)

exclude = if repo_available and og_tables_present, do: [], else: [:integration]

ExUnit.start(exclude: exclude)
