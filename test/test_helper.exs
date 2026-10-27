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

      # Core's versioned migration chain first.
      PhoenixKit.Migration.ensure_current(TestRepo, log: false)

      # The OG tables belong to this module's chain (core 3.0 creates none), so
      # build them with it: the real chain, as `mix phoenix_kit.update` runs it.
      PhoenixKitOG.Migrations.up_statements("public")
      |> Enum.each(&TestRepo.query!(&1))

      og_tables? = true

      Application.put_env(:phoenix_kit_og, :og_tables_present, og_tables?)

      # Tests that fake catalog states (`UPDATE pg_index ...`) need a
      # superuser; CI and dev roles often are not one.
      %{rows: [[superuser?]]} =
        TestRepo.query!("SELECT rolsuper FROM pg_roles WHERE rolname = current_user")

      Application.put_env(:phoenix_kit_og, :db_superuser, superuser?)

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

exclude =
  if Application.get_env(:phoenix_kit_og, :db_superuser, false) do
    exclude
  else
    [:requires_superuser | exclude]
  end

# The builds-alone test needs `PhoenixKit.TestSupport.ModuleChainCheck`, which
# ships in the first core release after 2.64.1; against an older core it is
# excluded.
chain_check_exclude =
  if Code.ensure_loaded?(PhoenixKit.TestSupport.ModuleChainCheck),
    do: [],
    else: [:requires_module_chain_check]

ExUnit.start(exclude: chain_check_exclude ++ exclude)

# The manifest test builds the module's tables with `ModuleChainCheck.build_alone/4`
# and hands the manifest to repair (`PhoenixKit.Module.expected_schema/0`); both
# arrive in the first core release after 2.64.1.
unless Code.ensure_loaded?(PhoenixKit.TestSupport.ModuleChainCheck) and
         function_exported?(PhoenixKit.TestSupport.ModuleChainCheck, :build_alone, 4) do
  ExUnit.configure(exclude: [:requires_core_expected_schema | ExUnit.configuration()[:exclude]])
end
