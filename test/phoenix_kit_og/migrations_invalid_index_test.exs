defmodule PhoenixKitOG.MigrationsInvalidIndexTest do
  use PhoenixKitOG.DataCase, async: false

  alias Ecto.Migration.Runner
  alias PhoenixKit.Migrations.Postgres.Helpers
  alias PhoenixKitOG.Migrations
  alias PhoenixKitOG.Test.Repo

  @moduledoc """
  Regression test for the invalid-index self-heal `index_guard/8` adds over
  the sibling migration chains in this workspace (`grep -rl indisvalid`
  across the other `phoenix_kit_*` chains returns nothing — this is new;
  see `PhoenixKitOG.Migrations`' moduledoc, "Invalid-index handling").

  A `CREATE INDEX CONCURRENTLY` that gets interrupted (a crashed migration,
  a killed connection) leaves an INVALID index behind under its real,
  canonical name — Postgres does not clean it up automatically. A bare
  `CREATE INDEX IF NOT EXISTS <name> ...` is then a permanent no-op against
  that broken object: `IF NOT EXISTS` only checks whether a relation of
  that name exists at all, not whether it is valid. `index_guard/8` fixes
  this with a DROP-first pass, gated on `i.indisvalid = false` and an exact
  name match, immediately ahead of the normal semantic existence check.

  Simulated here the same way the adversarial verification pass for this
  series does it: rather than actually crashing a `CREATE INDEX
  CONCURRENTLY` mid-flight (slow, flaky, and Postgres-version-dependent to
  set up deterministically), the catalog is mutated directly —
  `UPDATE pg_index SET indisvalid = false` — which is exactly the end state
  a crashed `CONCURRENTLY` build leaves behind. This is a deliberate,
  test-only catalog mutation; nothing in this chain's own DDL ever does
  this itself.

  Covers both a plain, non-unique index (`idx_og_assignments_template`) and
  a partial UNIQUE index (`idx_og_assignments_unique_scoped`) — the fix
  must not depend on uniqueness or a partial predicate.

  `async: false` — shares the migrator's sandbox connection, like the other
  migration test files that run a real `up/1`.

  Tagged `:requires_superuser`: writing to `pg_index` is superuser-only, so
  `test_helper.exs` excludes this file when the test role is not one.
  """

  @moduletag :requires_superuser

  @prefix "pkoginvalididx_host"

  defmodule RunUpToOneInvalidIndexHost do
    @moduledoc false
    use Ecto.Migration

    def up, do: PhoenixKitOG.Migrations.up(prefix: "pkoginvalididx_host", version: 1)
    def down, do: :ok
  end

  setup do
    Repo.query!("CREATE SCHEMA IF NOT EXISTS #{@prefix}")

    Helpers.ensure_extension!(Repo, "pgcrypto")
    Helpers.ensure_uuid_v7_function(Repo, @prefix)

    # Canonical shape, canonical names, marker stamped by up_statements/2's
    # own last statement.
    Migrations.up_statements(@prefix, 1)
    |> Enum.each(&Repo.query!(&1))

    :ok
  end

  test "a plain index left invalid by a simulated crashed CONCURRENTLY build is dropped and recreated valid" do
    mark_invalid("idx_og_assignments_template")
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")

    run_migration(RunUpToOneInvalidIndexHost)

    assert index_valid?("idx_og_assignments_template")
    assert index_count_named("idx_og_assignments_template") == 1
    assert Migrations.migrated_version_runtime(prefix: @prefix) == 1
  end

  test "a partial UNIQUE index left invalid by a simulated crashed CONCURRENTLY build is dropped and recreated valid" do
    mark_invalid("idx_og_assignments_unique_scoped")
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")

    run_migration(RunUpToOneInvalidIndexHost)

    assert index_valid?("idx_og_assignments_unique_scoped")
    assert index_count_named("idx_og_assignments_unique_scoped") == 1
    assert Migrations.migrated_version_runtime(prefix: @prefix) == 1
  end

  test "recovering an invalid index is idempotent across a second up/1 run" do
    mark_invalid("idx_og_assignments_template")
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")

    run_migration(RunUpToOneInvalidIndexHost)
    assert index_valid?("idx_og_assignments_template")
    assert index_count_named("idx_og_assignments_template") == 1

    # Already valid now — a second run must be a genuine no-op, not attempt
    # another drop/recreate cycle.
    Repo.query!("COMMENT ON TABLE #{@prefix}.phoenix_kit_og_templates IS NULL")
    run_migration(RunUpToOneInvalidIndexHost)

    assert index_valid?("idx_og_assignments_template")
    assert index_count_named("idx_og_assignments_template") == 1
    assert Migrations.migrated_version_runtime(prefix: @prefix) == 1
  end

  # ── helpers ──────────────────────────────────────────────────────────

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

  defp mark_invalid(name) do
    Repo.query!(
      "UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{@prefix}.#{name}'::regclass"
    )
  end

  defp index_valid?(name) do
    %{rows: [[valid?]]} =
      Repo.query!(
        "SELECT indisvalid FROM pg_index WHERE indexrelid = '#{@prefix}.#{name}'::regclass"
      )

    valid?
  end

  defp index_count_named(name) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_indexes WHERE schemaname = $1 AND indexname = $2",
        [@prefix, name]
      )

    count
  end
end
