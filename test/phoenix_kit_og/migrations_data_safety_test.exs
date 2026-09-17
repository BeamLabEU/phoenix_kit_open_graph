defmodule PhoenixKitOG.MigrationsDataSafetyTest do
  use PhoenixKitOG.DataCase, async: false

  alias Ecto.Migration.Runner
  alias PhoenixKitOG.Assignments
  alias PhoenixKitOG.Migrations
  alias PhoenixKitOG.SceneStore
  alias PhoenixKitOG.Schemas.Assignment
  alias PhoenixKitOG.Schemas.Template
  alias PhoenixKitOG.Templates
  alias PhoenixKitOG.Test.Repo

  @moduledoc """
  The acceptance a full 2-table row chain actually needs, and that no static
  test can give: REAL rows, a REAL `down/1` run as a migration, and the rows
  still there afterwards, byte-for-byte.

  `migrations_test.exs` proves what the chain BUILDS (no
  DROP/TRUNCATE/DELETE token anywhere reachable from `down_statements/2`,
  `down/1` emits marker bookkeeping only). That is a proof about text. This
  file proves what the chain DOES to a database that holds a real template
  and two real assignments (one default-tier, `scope_uuid: nil`; one
  scoped, with a real `scope_uuid`) — seeded through this module's own
  public contexts (`Templates`, `Assignments`), not hand-inserted rows.

  The last test is the mutation check: it runs the same survival harness
  against a deliberately destructive rollback and requires it to FAIL.
  Without that, a survival assertion that silently stopped asserting (wrong
  table name, empty row set) would stay green forever and prove nothing.

  `async: false` — the migrator wants the shared sandbox connection.
  """

  defmodule RollbackToZero do
    @moduledoc false
    use Ecto.Migration

    def up, do: Migrations.down(prefix: "public", version: 0)
    def down, do: :ok
  end

  defmodule RollbackToOneFromMap do
    @moduledoc false
    use Ecto.Migration

    # Deliberately the MAP shape: it is accepted, so it must carry
    # `:version` like the keyword list does.
    def up, do: Migrations.down(%{prefix: "public", version: 1})
    def down, do: :ok
  end

  defmodule DestructiveRollback do
    @moduledoc false
    use Ecto.Migration

    # NOT what the package ships — the mutant the survival check must catch.
    def up do
      execute("DELETE FROM public.phoenix_kit_og_assignments")
      execute("DELETE FROM public.phoenix_kit_og_templates")
    end

    def down, do: :ok
  end

  defmodule RunUpToOne do
    @moduledoc false
    use Ecto.Migration

    def up, do: Migrations.up(prefix: "public", version: 1)
    def down, do: :ok
  end

  setup do
    {:ok, template} =
      Templates.create(%{
        "name" => "Data Safety Template #{System.unique_integer([:positive])}",
        "canvas" => SceneStore.dump(SceneStore.blank())
      })

    {:ok, default_assignment} = Assignments.set("data_safety", "default", nil, template.uuid)

    scope_uuid = Ecto.UUID.generate()

    {:ok, scoped_assignment} =
      Assignments.set("data_safety", "group", scope_uuid, template.uuid)

    {:ok,
     template: template,
     default_assignment: default_assignment,
     scoped_assignment: scoped_assignment}
  end

  test "a real down(version: 0) leaves every seeded row alive, across both tables",
       %{template: template, default_assignment: default_assignment, scoped_assignment: scoped} do
    counts_before = all_counts()

    run_migration(RollbackToZero)

    assert all_counts() == counts_before,
           "rolling this chain back changed at least one of the 2 tables' row counts: " <>
             "before=#{inspect(counts_before)} after=#{inspect(all_counts())}"

    reloaded_template = Repo.get!(Template, template.uuid)
    assert reloaded_template.name == template.name

    reloaded_default = Repo.get!(Assignment, default_assignment.uuid)
    assert reloaded_default.template_uuid == template.uuid
    assert reloaded_default.scope_uuid == nil

    reloaded_scoped = Repo.get!(Assignment, scoped.uuid)
    assert reloaded_scoped.template_uuid == template.uuid
    assert reloaded_scoped.scope_uuid == scoped.scope_uuid
  end

  test "the rollback still does its one real job: the marker is cleared" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_og_templates IS 'pkog_schema:1'")
    assert Migrations.migrated_version_runtime(prefix: "public") == 1

    run_migration(RollbackToZero)

    assert Migrations.migrated_version_runtime(prefix: "public") == 0
  end

  test "a rollback to version 1 passed as a map stops at 1, not at 0" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_og_templates IS 'pkog_schema:1'")

    run_migration(RollbackToOneFromMap)

    assert Migrations.migrated_version_runtime(prefix: "public") == 1,
           "the map shape lost :version and rolled the chain further back than asked"
  end

  test "a real up(version: 1) run is idempotent and leaves seeded rows untouched",
       %{template: template} do
    # up/1 re-reads the installed version, calls ensure_extension!/1 and
    # ensure_uuid_v7_function/1, then runs the same guarded statements
    # up_statements/2 emits — clearing the marker first simulates the
    # "database behind the target" branch up/1 checks before doing anything,
    # so this exercises that whole path for real rather than as SQL text
    # applied directly (test_helper.exs does the latter, once, before any
    # test runs — this is the only place up/1 itself, as a function, gets a
    # real migration-context run).
    counts_before = all_counts()

    Repo.query!("COMMENT ON TABLE phoenix_kit_og_templates IS NULL")

    run_migration(RunUpToOne)

    assert Migrations.migrated_version_runtime(prefix: "public") == 1

    assert all_counts() == counts_before,
           "a real up(version: 1) run changed at least one of the 2 tables' row counts"

    assert Repo.get!(Template, template.uuid).name == template.name

    # Idempotence: every table/pkey/unique-constraint/index/fk statement is
    # CREATE-IF-NOT-EXISTS/DO-guarded against objects that already exist
    # (core's baseline created them), so running up/1 again must be a no-op,
    # not an error. Clear the marker again first — otherwise this second
    # call is just a version-gate no-op that never re-reaches the guarded
    # statements, which would prove the gate works but not the guards.
    Repo.query!("COMMENT ON TABLE phoenix_kit_og_templates IS NULL")
    run_migration(RunUpToOne)
    assert Migrations.migrated_version_runtime(prefix: "public") == 1
    assert all_counts() == counts_before
  end

  test "the survival check has teeth: a destructive rollback fails it", %{template: template} do
    counts_before = all_counts()

    run_migration(DestructiveRollback)

    # The same assertions the real test makes. Both must fail here, or the
    # real test above is decoration.
    assert_raise ExUnit.AssertionError, fn ->
      assert all_counts() == counts_before
    end

    assert_raise Ecto.NoResultsError, fn ->
      Repo.get!(Template, template.uuid)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Runs the migration IN THIS PROCESS, through Ecto's own migration runner,
  # rather than `Ecto.Migrator.up/4`. The Migrator runs the migration inside a
  # `Task`, which then has to check out the sandbox connection this test
  # already owns — it never gets it, and every assertion below dies in the
  # checkout queue instead of testing the rollback. The runner is what the
  # Migrator itself calls once it has dealt with locking and version
  # bookkeeping; going straight to it keeps the real migration context (so
  # `execute/1` inside `down/1` is the real `execute/1`) and drops only the
  # parts this file is not about.
  defp run_migration(module) do
    Runner.run(
      Repo,
      [],
      :os.system_time(:microsecond),
      module,
      :forward,
      :up,
      :up,
      log: false,
      log_migrations_sql: false
    )
  end

  @tables ~w(phoenix_kit_og_templates phoenix_kit_og_assignments)

  defp all_counts, do: Map.new(@tables, &{&1, count(&1)})

  defp count(table) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}")
    count
  end
end
