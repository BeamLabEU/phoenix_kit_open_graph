defmodule PhoenixKitOG.MigrationsRenamedHostTest do
  use PhoenixKitOG.DataCase, async: false

  alias Ecto.Migration.Runner
  alias PhoenixKit.Migrations.Postgres.Helpers
  alias PhoenixKitOG.Migrations
  alias PhoenixKitOG.Test.Repo

  @moduledoc """
  Reproduces a renamed-host shape: every PK/FK/UNIQUE-constraint/index on
  both `phoenix_kit_og_*` tables renamed to an arbitrary different name, the
  way a real host-level rename migration leaves objects behind — see
  `PhoenixKitOG.Migrations`' moduledoc, "Guards are semantic, not
  name-based", for the sibling incidents this defends against
  (`phoenix_kit_posts` ended up with 3 duplicate UNIQUE indexes from a
  name-based guard after a host-level rename, and a first cut of
  `PhoenixKitNewsletters.Migrations` crashed outright on a renamed host with
  `42P16 multiple primary keys`).

  The fixture is built from this chain's OWN `up_statements(@prefix, 1)`
  output (gets the correct, canonical shape for free — no
  `phoenix_kit_users` stand-in needed, since this chain's only FK target is
  its own `phoenix_kit_og_templates`, already created by that same output),
  then every constraint and index is renamed to something else, and the
  marker is cleared — so the starting point is "the right shape, wrong
  names, never stamped by this chain".

  One wrinkle verified empirically (same as the sibling `publishing` chain's
  identical test): `ALTER TABLE ... RENAME CONSTRAINT` RENAMES A
  PK/UNIQUE CONSTRAINT'S OWN BACKING INDEX TOO (a constraint backed by an
  index is not a separate rename target). Only the 1 FK (which has no
  backing index) and the 3 free-standing `idx_og_assignments_*` indexes
  need a SEPARATE `ALTER INDEX ... RENAME TO` pass, queried fresh AFTER the
  constraint renames so it never touches an index that renaming its
  constraint already renamed.

  Everything here runs against an isolated `pkogrenamed_host` prefix schema
  inside the sandboxed test transaction (Postgres DDL is transactional, so
  it rolls back with everything else at `on_exit` — no manual cleanup).

  `async: false` — shares the migrator's sandbox connection, like
  `migrations_data_safety_test.exs`.
  """

  @prefix "pkogrenamed_host"

  @tables ~w(phoenix_kit_og_templates phoenix_kit_og_assignments)

  defmodule RunUpToOneRenamedHost do
    @moduledoc false
    use Ecto.Migration

    def up, do: PhoenixKitOG.Migrations.up(prefix: "pkogrenamed_host", version: 1)
    def down, do: :ok
  end

  setup do
    Repo.query!("CREATE SCHEMA IF NOT EXISTS #{@prefix}")

    # `uuid_generate_v7()` must exist in @prefix BEFORE the fixture's own
    # CREATE TABLE statements run — every "uuid" column's DEFAULT clause
    # references it by name, and Postgres validates a DEFAULT expression
    # against real catalog objects at CREATE TABLE time. pgcrypto itself is
    # already ensured by the main test suite's own migration bootstrap
    # (database-wide, not schema-scoped), so only the schema-qualified
    # function needs creating here.
    Helpers.ensure_extension!(Repo, "pgcrypto")
    Helpers.ensure_uuid_v7_function(Repo, @prefix)

    # The exact current (post-adoption) shape, under this chain's own
    # canonical names — built from the builder itself, not hand-typed, so
    # this fixture can never silently drift from what up_statements/2
    # actually emits.
    Migrations.up_statements(@prefix, 1)
    |> Enum.each(&Repo.query!(&1))

    rename_every_constraint()
    rename_every_remaining_index()

    # The marker above was stamped only because up_statements/2's own last
    # statement is the marker COMMENT — clear it, since this fixture
    # represents a host that has never run THIS chain (an independent
    # history that happens to already have the right shape post-rename),
    # not one that ran it once already.
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")

    :ok
  end

  test "up/1 against a host whose PK/FK/UNIQUE-constraint/index objects carry arbitrary " <>
         "names does not error, does not duplicate any object, and still stamps the marker" do
    # This is the regression itself: a name-based PK guard raises
    # "multiple primary keys for table ... are not allowed" here.
    run_migration(RunUpToOneRenamedHost)

    # Every table still has exactly ONE primary key, under its renamed name
    # — no second, canonically-named PK was added alongside it.
    for {table, expected_columns} <- pkey_tables() do
      pkeys = pkey_rows(table)
      assert length(pkeys) == 1, "#{table}: expected exactly 1 primary key, got #{inspect(pkeys)}"
      {name, columns} = hd(pkeys)

      assert String.starts_with?(name, "z_"),
             "#{table}: pkey #{name} was not left under its renamed name"

      assert columns == expected_columns
    end

    # The 1 UNIQUE constraint (not a PK) is untouched under its renamed name
    # — no duplicate, canonically-named UNIQUE constraint was added.
    unique_constraints = constraint_rows("phoenix_kit_og_templates", "u")
    assert length(unique_constraints) == 1
    {uniq_name, uniq_columns} = hd(unique_constraints)
    assert String.starts_with?(uniq_name, "z_")
    assert uniq_columns == ["name"]

    # The 1 FK is untouched under its renamed name — no duplicate,
    # differently-named FK was added alongside it.
    fks = fk_rows("phoenix_kit_og_assignments")
    assert length(fks) == 1
    assert Enum.all?(fks, fn {name, _target} -> String.starts_with?(name, "z_") end)

    # All 3 free-standing indexes are untouched under their renamed names —
    # no duplicate, canonically-named index was added.
    for table <- @tables do
      free_standing = free_standing_index_names(table)

      assert Enum.all?(free_standing, &String.starts_with?(&1, "z_")),
             "#{table}: at least one free-standing index is not under its renamed name: #{inspect(free_standing)}"
    end

    assert total_index_count() == 6,
           "expected exactly 6 indexes across both tables (3 free-standing + 2 pkey-backing " <>
             "+ 1 unique-constraint-backing) — a different count means something was duplicated " <>
             "or never created"

    assert Migrations.migrated_version_runtime(prefix: @prefix) == 1
  end

  test "a second up/1 run against the same renamed-host shape is idempotent" do
    run_migration(RunUpToOneRenamedHost)

    # up/1 short-circuits on `migrated_version(opts) < opts.version` — without
    # clearing the marker here, this second call would be a version-gate
    # no-op that never re-reaches the guarded statements, and "idempotent"
    # would be true for the wrong reason. Clearing it forces every guard to
    # run again against the now-canonically-shaped (post-1st-run) table, the
    # real idempotence claim this test makes.
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")
    run_migration(RunUpToOneRenamedHost)

    # Still exactly one PK per table, 4 constraints (2 pkeys + 1 unique + 1
    # fk), 6 indexes, still version 1 — a second run must not add a THIRD
    # copy of anything.
    for {table, _} <- pkey_tables() do
      assert length(pkey_rows(table)) == 1
    end

    assert length(constraint_rows("phoenix_kit_og_templates", "u")) == 1
    assert length(fk_rows("phoenix_kit_og_assignments")) == 1
    assert total_index_count() == 6

    assert Migrations.migrated_version_runtime(prefix: @prefix) == 1
  end

  # ── fixture setup helpers ───────────────────────────────────────────────

  defp rename_every_constraint do
    for table <- @tables, {old_name} <- constraint_names(table) do
      new_name = "z_" <> old_name
      Repo.query!("ALTER TABLE #{@prefix}.#{table} RENAME CONSTRAINT #{old_name} TO #{new_name}")
    end
  end

  # Queried AFTER the constraint renames, on purpose — renaming a PK/UNIQUE
  # constraint already renamed its own backing index (verified live, see
  # moduledoc), so an index whose name already starts with "z_" here is one
  # of those and must be left alone; renaming it again would just be
  # renaming an already-renamed object, which is harmless but pointless —
  # skipped instead, so this loop only ever touches the 3 free-standing
  # `idx_og_assignments_*` indexes.
  defp rename_every_remaining_index do
    for table <- @tables,
        {old_name} <- all_index_names(table),
        not String.starts_with?(old_name, "z_") do
      new_name = "z_" <> old_name
      Repo.query!("ALTER INDEX #{@prefix}.#{old_name} RENAME TO #{new_name}")
    end
  end

  defp constraint_names(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT conname FROM pg_constraint WHERE conrelid = '#{@prefix}.#{table}'::regclass AND contype IN ('p', 'u', 'f')"
      )

    Enum.map(rows, &List.to_tuple/1)
  end

  defp all_index_names(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT indexname FROM pg_indexes WHERE schemaname = $1 AND tablename = $2",
        [@prefix, table]
      )

    Enum.map(rows, &List.to_tuple/1)
  end

  # ── assertion helpers ────────────────────────────────────────────────────

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

  defp pkey_tables do
    %{
      "phoenix_kit_og_templates" => ["uuid"],
      "phoenix_kit_og_assignments" => ["uuid"]
    }
  end

  defp pkey_rows(table), do: constraint_rows(table, "p")

  defp constraint_rows(table, contype) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT c.conname,
               (SELECT array_agg(a.attname ORDER BY k.ord)
                FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum)
        FROM pg_constraint c
        WHERE c.conrelid = '#{@prefix}.#{table}'::regclass AND c.contype = $1
        """,
        [contype]
      )

    Enum.map(rows, fn [name, columns] -> {name, columns} end)
  end

  defp fk_rows(table) do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.conname, confrelid::regclass::text
      FROM pg_constraint c
      WHERE c.conrelid = '#{@prefix}.#{table}'::regclass AND c.contype = 'f'
      """)

    Enum.map(rows, fn [name, target] -> {name, target} end)
  end

  defp free_standing_index_names(table) do
    pkey_backed = constraint_rows(table, "p") |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    unique_backed =
      if table == "phoenix_kit_og_templates" do
        constraint_rows(table, "u") |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      else
        MapSet.new()
      end

    backed = MapSet.union(pkey_backed, unique_backed)

    table
    |> all_index_names()
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&MapSet.member?(backed, &1))
  end

  defp total_index_count do
    Enum.reduce(@tables, 0, fn table, acc -> acc + length(all_index_names(table)) end)
  end
end
