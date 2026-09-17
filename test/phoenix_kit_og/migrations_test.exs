defmodule PhoenixKitOG.MigrationsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitOG.Migrations

  @moduledoc """
  Pins the ownership design for `phoenix_kit_og`: this package owns both
  `phoenix_kit_og_*` tables' FUTURE shape through its module migration
  chain, while core's `V154` baseline still creates both of them on every
  install, and the chain's V1 merely ADOPTS that shape (stamps the
  `pkog_schema:` marker on the anchor table, `phoenix_kit_og_templates`,
  changes no shape at all — see `PhoenixKitOG.Migrations`' moduledoc).

  Every test here is a pure data/string assertion over
  `up_statements/2`/`down_statements/2`/`up/1`/`down/1`-as-source-text and
  core's static `PhoenixKit.Migrations.ExpectedSchema.objects/1` manifest —
  none of them touch a database (see `migrations_runtime_test.exs`,
  `migrations_renamed_host_test.exs`, `migrations_expression_index_test.exs`,
  `migrations_invalid_index_test.exs`, and `migrations_data_safety_test.exs`
  for the database-backed suites).

  Unlike `PhoenixKitPublishing.Migrations` (this chain's closest sibling in
  spirit), neither table here carries a CHECK constraint, so there is no
  check-guard section and no CHECK-name-or-definition fallback to test —
  see `Migrations`' own moduledoc, "Ownership situation". A test below
  ("no check_guard helper") asserts the absence directly, so a future edit
  that copies a CHECK guard in from a sibling chain without adapting it is
  caught rather than silently shipped.
  """

  @og_tables ~w(phoenix_kit_og_templates phoenix_kit_og_assignments)

  test "PhoenixKitOG declares the module-owned migration chain" do
    # Assert the VALUE, not `function_exported?/3` — `use PhoenixKit.Module`
    # injects an overridable default `migration_module/0`, so exportedness
    # says nothing about whether this module declares one.
    assert Code.ensure_loaded?(PhoenixKitOG)

    assert PhoenixKitOG.migration_module() == Migrations,
           """
           PhoenixKitOG no longer declares its migration chain \
           (migration_module/0 returned #{inspect(PhoenixKitOG.migration_module())}).

           The chain is how phoenix_kit_og's future shape is versioned
           (pkog_schema marker) and how `mix phoenix_kit.update` migrates hosts.
           """
  end

  describe "the coordinator implements the protocol" do
    alias PhoenixKit.Migrations.Postgres.Helpers

    test "current_version/0 and version_table/0" do
      assert Migrations.current_version() == 1
      assert Migrations.version_table() == "phoenix_kit_og_templates"
    end

    test "initial_version/0" do
      assert Migrations.initial_version() == 1
    end

    # `mix phoenix_kit_hello_world.audit_migrations` (the canonical auditor
    # for this protocol) refuses to drive a coordinator missing any of these
    # five — `mix phoenix_kit.update` itself only calls
    # `migrated_version_runtime/1` + `current_version/0`, but `up/1` needs
    # `migrated_version/1` to re-read the version it is about to change.
    test "exports the full five-function protocol, plus version_table/0 and initial_version/0" do
      for {fun, arity} <- [
            {:current_version, 0},
            {:up, 1},
            {:down, 1},
            {:migrated_version, 1},
            {:migrated_version_runtime, 1},
            {:version_table, 0},
            {:initial_version, 0}
          ] do
        assert function_exported?(Migrations, fun, arity),
               "#{inspect(Migrations)} does not export #{fun}/#{arity}"
      end
    end

    # The marker decides whether any LATER version ever runs: core's
    # `classify/2` reads it and answers `:up_to_date` for every version at or
    # below it. Stamping a version this chain does not have therefore skips
    # V2 and everything after it, silently and permanently.
    test "refuses to stamp a version this chain does not have" do
      too_high = Migrations.current_version() + 1

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.up_statements("public", too_high)
      end

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.down_statements("public", too_high)
      end

      # The ceiling itself stays reachable, or the guard would just break
      # the chain instead of bounding it.
      assert Migrations.up_statements("public", Migrations.current_version()) != []
    end

    # `validate_target!` also gates `migrated_version/1` and
    # `migrated_version_runtime/1` (both default their target to
    # `initial_version/0`, well under the ceiling) — 0 and 1 must both stay
    # reachable for every public builder.
    test "validate_target! admits 0 and 1, and nothing above current_version/0" do
      for target <- [0, 1] do
        assert Migrations.up_statements("public", target) |> is_list()
        assert Migrations.down_statements("public", target) |> is_list()
      end

      assert_raise ArgumentError, fn -> Migrations.up_statements("public", 2) end
      assert_raise ArgumentError, fn -> Migrations.down_statements("public", 2) end
    end

    # This chain interpolates the prefix into every object it creates, and
    # Postgres TRUNCATES an identifier past 63 bytes silently rather than
    # rejecting it — so a prefix core would refuse yields object names that
    # differ from core's while every command still exits 0, breaking the
    # contract adoption rests on. The rules are therefore core's, and this
    # test compares against core rather than restating them.
    test "every public builder that emits SQL validates its own prefix" do
      for fun <- [:up_statements, :down_statements] do
        assert_raise ArgumentError, fn -> apply(Migrations, fun, ["EVIL\";DROP"]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [String.duplicate("a", 30)]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [123]) end
      end
    end

    test "invalid prefix error shape matches Helpers.validate_prefix!/1's own" do
      for fun <- [:up_statements, :down_statements] do
        error =
          try do
            apply(Migrations, fun, ["Bad-Prefix"])
            flunk("expected #{fun} to raise for an invalid prefix")
          rescue
            e in ArgumentError -> e
          end

        assert Exception.message(error) =~ "invalid PhoenixKit schema prefix"
      end

      for fun <- [:migrated_version, :migrated_version_runtime] do
        assert_raise ArgumentError, ~r/invalid PhoenixKit schema prefix/, fn ->
          apply(Migrations, fun, [[prefix: "Bad-Prefix"]])
        end
      end
    end

    test "the prefix rules are core's, case and length included" do
      for prefix <- [
            "public",
            "og_alt",
            "OpenGraph",
            "9leading_digit",
            "has-dash",
            String.duplicate("a", 20),
            String.duplicate("a", 21),
            String.duplicate("a", 30)
          ] do
        core_accepts =
          try do
            Helpers.validate_prefix!(prefix)
            true
          rescue
            ArgumentError -> false
          end

        ours_accepts =
          try do
            Migrations.up_statements(prefix)
            true
          rescue
            ArgumentError -> false
          end

        assert ours_accepts == core_accepts,
               "prefix #{inspect(prefix)}: core #{if core_accepts, do: "accepts", else: "rejects"}, " <>
                 "this chain #{if ours_accepts, do: "accepts", else: "rejects"} — the two must agree, " <>
                 "or the object names this chain creates stop matching core's"
      end
    end

    test "rejects a prefix that cannot be safely interpolated into DDL" do
      for bad <- ["public.\"; DROP TABLE x; --", "1st", "a-b", ""] do
        assert_raise ArgumentError, fn -> Migrations.up_statements(bad) end
        assert_raise ArgumentError, fn -> Migrations.down_statements(bad, 0) end
      end
    end
  end

  describe "the chain's per-version statement content is pinned (drift guard)" do
    # V1 is a PUBLISHED version once this ships. A host that has already run
    # it will never run it again, so editing its content does not "fix" that
    # host — it silently splits fresh installs from existing ones. Pinning
    # the exact normalised text makes that split a deliberate, visible diff
    # instead of an accidental one buried in a refactor.
    #
    # Captured from a REAL run of `up_statements("public", 1)` in this same
    # process (`mix run`, then pasted verbatim) — never hand-typed.
    defp normalised(statements),
      do: Enum.map(statements, &(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))

    test "V1's published statements are frozen" do
      v1 = Migrations.up_statements("public", 1) |> normalised()

      assert v1 == [
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_og_templates ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"name\" character varying(255) NOT NULL, \"description\" character varying(1024), \"canvas\" jsonb DEFAULT '{}'::jsonb NOT NULL, \"preview_image_uuid\" uuid, \"inserted_at\" timestamp with time zone DEFAULT now() NOT NULL, \"updated_at\" timestamp with time zone DEFAULT now() NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_og_assignments ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"module_key\" character varying(64) NOT NULL, \"scope_type\" character varying(32) NOT NULL, \"scope_uuid\" uuid, \"template_uuid\" uuid NOT NULL, \"slot_mapping\" jsonb DEFAULT '{}'::jsonb NOT NULL, \"inserted_at\" timestamp with time zone DEFAULT now() NOT NULL, \"updated_at\" timestamp with time zone DEFAULT now() NOT NULL )",
               "ALTER TABLE public.phoenix_kit_og_assignments ADD COLUMN IF NOT EXISTS slot_mapping JSONB NOT NULL DEFAULT '{}'",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint WHERE conrelid = 'public.phoenix_kit_og_templates'::regclass AND contype = 'p' ) THEN ALTER TABLE public.phoenix_kit_og_templates ADD CONSTRAINT phoenix_kit_og_templates_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint WHERE conrelid = 'public.phoenix_kit_og_assignments'::regclass AND contype = 'p' ) THEN ALTER TABLE public.phoenix_kit_og_assignments ADD CONSTRAINT phoenix_kit_og_assignments_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint WHERE conrelid = 'public.phoenix_kit_og_templates'::regclass AND contype = 'u' AND array_length(conkey, 1) = 1 AND ( SELECT array_agg(a.attname ORDER BY k.ord) FROM unnest(conkey) WITH ORDINALITY AS k(attnum, ord) JOIN pg_attribute a ON a.attrelid = conrelid AND a.attnum = k.attnum ) = ARRAY['name']::name[] ) THEN ALTER TABLE public.phoenix_kit_og_templates ADD CONSTRAINT phoenix_kit_og_templates_name_uniq UNIQUE (name); END IF; END $$",
               "DO $$ BEGIN IF EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid WHERE ic.relname = 'idx_og_assignments_unique_scoped' AND ic.relnamespace = 'public'::regnamespace AND i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisvalid = false ) THEN DROP INDEX public.idx_og_assignments_unique_scoped; END IF; IF NOT EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid JOIN pg_am am ON am.oid = ic.relam WHERE i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisunique = true AND i.indisvalid AND am.amname = 'btree' AND i.indexprs IS NULL AND array_length(i.indkey::int2[], 1) = 3 AND pg_get_expr(i.indpred, i.indrelid) = '(scope_uuid IS NOT NULL)' AND ( SELECT array_agg(elem ORDER BY ord) FROM unnest(i.indoption::int2[]) WITH ORDINALITY AS u(elem, ord) ) = ARRAY[0, 0, 0]::int2[] AND ( SELECT array_agg(a.attname ORDER BY k.ord) FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum ) = ARRAY['module_key', 'scope_type', 'scope_uuid']::name[] ) THEN EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS idx_og_assignments_unique_scoped ON public.phoenix_kit_og_assignments USING btree (module_key, scope_type, scope_uuid) WHERE (scope_uuid IS NOT NULL)'; END IF; END $$",
               "DO $$ BEGIN IF EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid WHERE ic.relname = 'idx_og_assignments_unique_default' AND ic.relnamespace = 'public'::regnamespace AND i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisvalid = false ) THEN DROP INDEX public.idx_og_assignments_unique_default; END IF; IF NOT EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid JOIN pg_am am ON am.oid = ic.relam WHERE i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisunique = true AND i.indisvalid AND am.amname = 'btree' AND i.indexprs IS NULL AND array_length(i.indkey::int2[], 1) = 2 AND pg_get_expr(i.indpred, i.indrelid) = '(scope_uuid IS NULL)' AND ( SELECT array_agg(elem ORDER BY ord) FROM unnest(i.indoption::int2[]) WITH ORDINALITY AS u(elem, ord) ) = ARRAY[0, 0]::int2[] AND ( SELECT array_agg(a.attname ORDER BY k.ord) FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum ) = ARRAY['module_key', 'scope_type']::name[] ) THEN EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS idx_og_assignments_unique_default ON public.phoenix_kit_og_assignments USING btree (module_key, scope_type) WHERE (scope_uuid IS NULL)'; END IF; END $$",
               "DO $$ BEGIN IF EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid WHERE ic.relname = 'idx_og_assignments_template' AND ic.relnamespace = 'public'::regnamespace AND i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisvalid = false ) THEN DROP INDEX public.idx_og_assignments_template; END IF; IF NOT EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid JOIN pg_am am ON am.oid = ic.relam WHERE i.indrelid = 'public.phoenix_kit_og_assignments'::regclass AND i.indisunique = false AND i.indisvalid AND am.amname = 'btree' AND i.indexprs IS NULL AND array_length(i.indkey::int2[], 1) = 1 AND i.indpred IS NULL AND ( SELECT array_agg(elem ORDER BY ord) FROM unnest(i.indoption::int2[]) WITH ORDINALITY AS u(elem, ord) ) = ARRAY[0]::int2[] AND ( SELECT array_agg(a.attname ORDER BY k.ord) FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord) JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum ) = ARRAY['template_uuid']::name[] ) THEN EXECUTE 'CREATE INDEX IF NOT EXISTS idx_og_assignments_template ON public.phoenix_kit_og_assignments USING btree (template_uuid)'; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint WHERE conrelid = 'public.phoenix_kit_og_assignments'::regclass AND contype = 'f' AND confrelid = 'public.phoenix_kit_og_templates'::regclass AND conkey = ARRAY[( SELECT attnum FROM pg_attribute WHERE attrelid = 'public.phoenix_kit_og_assignments'::regclass AND attname = 'template_uuid' )]::smallint[] ) THEN ALTER TABLE public.phoenix_kit_og_assignments ADD CONSTRAINT phoenix_kit_og_assignments_template_uuid_fkey FOREIGN KEY (template_uuid) REFERENCES public.phoenix_kit_og_templates(uuid) ON DELETE CASCADE; END IF; END $$",
               "COMMENT ON TABLE public.phoenix_kit_og_templates IS 'pkog_schema:1'"
             ]
    end
  end

  describe "the chain DDL adopts core's V154 shape" do
    test "V1 uses core's exact object names (shape-identical adoption)" do
      statements = Enum.join(Migrations.up_statements(), "\n")

      for name <- [
            "phoenix_kit_og_templates_pkey",
            "phoenix_kit_og_assignments_pkey",
            "phoenix_kit_og_templates_name_uniq",
            "idx_og_assignments_unique_scoped",
            "idx_og_assignments_unique_default",
            "idx_og_assignments_template",
            "phoenix_kit_og_assignments_template_uuid_fkey"
          ] do
        assert statements =~ name,
               "V1 no longer creates #{name} — it must stay shape-identical to core's V154"
      end
    end

    test "up stamps the version marker, and stamps it last" do
      statements = Migrations.up_statements()

      assert List.last(statements) ==
               "COMMENT ON TABLE public.phoenix_kit_og_templates IS 'pkog_schema:1'",
             "the marker must be stamped after the DDL it certifies, not before"
    end

    test "applying up to version 0 is not an operation" do
      assert Migrations.up_statements("public", 0) == []
      assert Migrations.up_statements("og_alt", 0) == []
    end

    test "every up statement is guarded (IF NOT EXISTS / DO-block idempotence)" do
      # V1 runs on installs where core's V154 already created everything, so
      # every statement must be a no-op against an object that is already
      # there. One exemption: the marker COMMENT — not a guarded operation,
      # it's the thing being stamped.
      exempt = ["COMMENT ON TABLE public.phoenix_kit_og_templates IS 'pkog_schema:1'"]

      ddl = Enum.reject(Migrations.up_statements(), &(&1 in exempt))

      for stmt <- ddl do
        assert stmt =~ "IF NOT EXISTS",
               "statement is not idempotent against a core-created table:\n#{stmt}"
      end
    end

    # No CHECK-constraint section at all, because neither table carries one
    # (confirmed by the moduledoc's three-source research pass). Every
    # guard (pkey, unique constraint, index, fk) is wrapped in its own
    # `DO $$ ... $$` block, so classification looks at what EACH block does,
    # not just that it is a `DO` block.
    test "statement sections appear in the order tables -> safety_net -> pkeys -> unique_constraints -> indexes -> fks -> marker" do
      statements = Migrations.up_statements()

      sections =
        Enum.map(statements, fn stmt ->
          cond do
            String.starts_with?(stmt, "CREATE TABLE") ->
              :table

            String.starts_with?(stmt, "COMMENT ON TABLE") ->
              :marker

            String.starts_with?(stmt, "ALTER TABLE") and stmt =~ "ADD COLUMN IF NOT EXISTS" ->
              :safety_net

            stmt =~ "PRIMARY KEY" ->
              :pkey

            stmt =~ "ADD CONSTRAINT" and stmt =~ " UNIQUE (" ->
              :unique_constraint

            stmt =~ "EXECUTE 'CREATE" ->
              :index

            stmt =~ "FOREIGN KEY" ->
              :fk
          end
        end)

      order = Enum.dedup(sections)

      assert order == [:table, :safety_net, :pkey, :unique_constraint, :index, :fk, :marker],
             "sections are out of order: #{inspect(order)}"
    end
  end

  describe "the chain can never destroy either table" do
    # Compared against the WHOLE expected content, not scanned for a
    # forbidden substring — a substring check only sees statements the
    # builder produced, so anything appended past it (a literal
    # `execute("DROP TABLE ...")` in `up/1`) would be invisible to it. That
    # path is closed by the source-text test below, which checks what is
    # executed rather than what is built.
    test "down/1 emits exactly the marker bookkeeping, in every target and prefix" do
      assert Migrations.down_statements("public", 0) ==
               ["COMMENT ON TABLE public.phoenix_kit_og_templates IS NULL"]

      assert Migrations.down_statements("public", 1) ==
               ["COMMENT ON TABLE public.phoenix_kit_og_templates IS 'pkog_schema:1'"]

      assert Migrations.down_statements("og_alt", 0) ==
               ["COMMENT ON TABLE og_alt.phoenix_kit_og_templates IS NULL"]

      assert Migrations.down_statements("og_alt", 1) ==
               ["COMMENT ON TABLE og_alt.phoenix_kit_og_templates IS 'pkog_schema:1'"]
    end

    # For `up/1` the expected content is the full set of OPERATIONS rather
    # than the full SQL text. An operation is `{verb, object}`, immune to
    # reformatting and still failing on any statement added, removed or
    # retargeted — including a destructive one, which cannot enter this set
    # without changing it. Captured from a real run, same as the pinned
    # literal list above.
    @up_operations [
      {"CREATE TABLE", "phoenix_kit_og_templates"},
      {"CREATE TABLE", "phoenix_kit_og_assignments"},
      {"ALTER TABLE", "phoenix_kit_og_assignments"},
      {"DO", "phoenix_kit_og_templates_pkey"},
      {"DO", "phoenix_kit_og_assignments_pkey"},
      {"DO", "phoenix_kit_og_templates_name_uniq"},
      {"CREATE UNIQUE INDEX", "idx_og_assignments_unique_scoped"},
      {"CREATE UNIQUE INDEX", "idx_og_assignments_unique_default"},
      {"CREATE INDEX", "idx_og_assignments_template"},
      {"DO", "phoenix_kit_og_assignments_template_uuid_fkey"},
      {"COMMENT ON TABLE", "phoenix_kit_og_templates"}
    ]

    test "up_statements/2 emits exactly these operations and no others" do
      for prefix <- ["public", "og_alt"] do
        actual = Enum.map(Migrations.up_statements(prefix), &operation/1)

        assert Enum.sort(actual) == Enum.sort(@up_operations),
               """
               up_statements(#{inspect(prefix)}) does not emit the expected set of
               operations.

               unexpected: #{inspect(Enum.sort(actual) -- Enum.sort(@up_operations))}
               missing:    #{inspect(Enum.sort(@up_operations) -- Enum.sort(actual))}

               Every statement this chain emits runs against a core-created
               table. Adding one is a chain version (V2+), not something to
               slip past this list.
               """
      end
    end

    test "the 2 real unique indexes are present, and only them" do
      unique_indexes =
        Migrations.up_statements()
        |> Enum.map(&operation/1)
        |> Enum.filter(&(elem(&1, 0) == "CREATE UNIQUE INDEX"))
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort()

      assert unique_indexes == [
               "idx_og_assignments_unique_default",
               "idx_og_assignments_unique_scoped"
             ]
    end

    test "every DROP INDEX in up_statements/2 sits inside its own invalid-index guard, never bare" do
      statements = Migrations.up_statements("public", 1)
      drop_index_statements = Enum.filter(statements, &(&1 =~ "DROP INDEX"))

      assert length(drop_index_statements) == 3,
             "expected exactly 1 DROP INDEX per index guard (3 indexes)"

      for stmt <- drop_index_statements do
        assert String.starts_with?(stmt, "DO $$\n"),
               "a DROP INDEX statement is not wrapped in its own guarded DO block:\n#{stmt}"

        assert stmt =~ "i.indisvalid = false",
               "a DROP INDEX statement's guard does not gate on the index being invalid:\n#{stmt}"

        assert stmt =~ "IF NOT EXISTS",
               "a DROP INDEX statement's DO block has no idempotent create path:\n#{stmt}"
      end
    end

    # `ON DELETE ...` is part of the foreign key's DEFINITION — the word
    # DELETE there describes what Postgres does to a child row when the
    # PARENT is deleted, and adoption reproducing core's FK means
    # reproducing core's referential action verbatim. Scanning the raw text
    # for the token would flag it, so the clause is removed before the scan.
    defp strip_referential_actions(statement) do
      String.replace(
        statement,
        ~r/ON\s+(DELETE|UPDATE)\s+(CASCADE|RESTRICT|NO\s+ACTION|SET\s+NULL|SET\s+DEFAULT)/i,
        "ON <referential action>"
      )
    end

    test "the referential-action strip does not blind the destructive scan" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      mutant =
        "ALTER TABLE public.phoenix_kit_og_assignments ADD CONSTRAINT x FOREIGN KEY (template_uuid) " <>
          "REFERENCES public.phoenix_kit_og_templates(uuid) ON DELETE CASCADE; DROP TABLE public.phoenix_kit_og_assignments"

      assert strip_referential_actions(mutant) =~ forbidden

      assert strip_referential_actions("DELETE FROM public.phoenix_kit_og_templates") =~ forbidden

      assert strip_referential_actions("TRUNCATE public.phoenix_kit_og_templates") =~ forbidden
    end

    # `up_statements/2` legitimately contains `DROP INDEX` text (inside each
    # index guard's invalid-index self-heal — see the moduledoc). That is
    # NOT scanned for here: this forbidden pattern is `DROP TABLE`, never
    # bare `DROP`, so a guarded `DROP INDEX` never trips it — the positive
    # test above ("every DROP INDEX ... never bare") is what proves each one
    # is safely conditional. `down_statements/2` is held to the stricter,
    # unconditional standard below: it never touches an index at all, so
    # ANY `DROP` there (not just `DROP TABLE`) is a bug.
    test "no statement in up_statements/2 can drop a table, truncate, or delete rows" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      for prefix <- ["public", "og_alt"] do
        for stmt <- Migrations.up_statements(prefix) do
          refute strip_referential_actions(stmt) =~ forbidden,
                 "up_statements(#{inspect(prefix)}) contains: #{stmt}"
        end
      end
    end

    test "down_statements/2 never contains DROP/TRUNCATE/DELETE of any kind" do
      forbidden = ~r/\b(DROP|TRUNCATE|DELETE)\b/i

      for prefix <- ["public", "og_alt"], target <- [0, 1] do
        for stmt <- Migrations.down_statements(prefix, target) do
          refute stmt =~ forbidden,
                 "down_statements(#{inspect(prefix)}, #{target}) contains: #{stmt}"
        end
      end
    end

    # `{verb, object}` for one statement. A pkey/unique-constraint/fk DO
    # block is identified by the constraint it adds; an index DO block
    # (guarded via `EXECUTE` — see the moduledoc's "Guards are semantic, not
    # name-based") is identified by the `CREATE [UNIQUE] INDEX` text inside
    # its own `EXECUTE '...'` argument, since the DO block's own verb says
    # nothing about either kind of target. An index guard's `DROP INDEX`
    # text (if present) never confuses this: the `EXECUTE '(CREATE|CREATE
    # UNIQUE)` check runs first and matches on the block containing it
    # regardless of what precedes it.
    defp operation(statement) do
      normalized = statement |> String.replace(~r/\s+/, " ") |> String.trim()

      cond do
        String.starts_with?(normalized, "DO ") and
            normalized =~ ~r/EXECUTE '(CREATE|CREATE UNIQUE)/ ->
          [_, verb, name] =
            Regex.run(
              ~r/EXECUTE '(CREATE UNIQUE INDEX|CREATE INDEX) IF NOT EXISTS (\w+)/,
              normalized
            )

          {verb, name}

        String.starts_with?(normalized, "DO ") ->
          [_, constraint] = Regex.run(~r/ADD CONSTRAINT (\w+)/, normalized)
          {"DO", constraint}

        true ->
          [_, verb, object] =
            Regex.run(
              ~r/^(CREATE UNIQUE INDEX|CREATE INDEX|CREATE TABLE|COMMENT ON TABLE|DROP TABLE|DROP INDEX|TRUNCATE|DELETE FROM|ALTER TABLE)(?: IF NOT EXISTS)? (?:\w+\.)?(\w+)/,
              normalized
            )

          {verb, object}
      end
    end
  end

  describe "what reaches the database is what the tests above inspect" do
    # The tests above read `up_statements/2` and `down_statements/2`. The
    # database gets `up/1` and `down/1`. Nothing connected the two, so a
    # literal `execute("DROP TABLE ...")` written straight into `up/1` would
    # have passed every one of them — the guard was watching the data while
    # the function did the work.
    @source "lib/phoenix_kit_og/migrations.ex"

    test "neither direction executes SQL of its own" do
      source = File.read!(@source)

      refute source =~ ~r/execute\(/,
             """
             #{@source} calls execute/1 with an argument of its own.

             Every DDL statement this chain runs via execute/1 must come from
             up_statements/2 or down_statements/2, because those are what the
             tests above compare against their expected content. A statement
             executed directly (rather than piped in via &execute/1) is
             invisible to all of them. (up/1's own ensure_extension!/1 and
             ensure_uuid_v7_function/1 calls are unaffected by this check —
             they run their own idempotent setup outside of execute/1
             entirely, and are exercised for real by
             migrations_data_safety_test.exs instead.)
             """

      assert length(Regex.scan(~r/&execute\/1/, source)) == 2,
             "expected exactly two `&execute/1` references — one per direction — " <>
               "in #{@source}"
    end

    test "each direction executes its own builder" do
      source = File.read!(@source)

      assert source =~ ~r/up_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "up/1 no longer pipes up_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what the up_statements-based tests above check"

      assert source =~ ~r/down_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "down/1 no longer pipes down_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what `down/1 emits exactly the marker " <>
               "bookkeeping` checks"
    end

    # Scoped to the two functions' own bodies, not the whole file — the
    # moduledoc legitimately discusses "never drops a table" and "DROP
    # INDEX" in prose, which a whole-file, case-insensitive scan would flag
    # as a false positive on English words rather than SQL tokens.
    test "up/1 and down/1 themselves contain no DROP/TRUNCATE/DELETE token" do
      source = File.read!(@source)

      [up_body] = Regex.run(~r/def up\(.*?\n  end\n/s, source)
      [down_body] = Regex.run(~r/def down\(.*?\n  end\n/s, source)

      for {name, body} <- [{"up/1", up_body}, {"down/1", down_body}] do
        refute body =~ ~r/DROP|TRUNCATE|DELETE/i,
               "#{name}'s own body in #{@source} contains a DROP/TRUNCATE/DELETE token"
      end
    end

    # There is deliberately no CHECK-guard helper in this file (unlike
    # `PhoenixKitNewsletters.Migrations`, which needs one for real CHECK
    # constraints) — see this file's moduledoc, "Ownership situation":
    # neither table carries a CHECK constraint. A future edit that copies a
    # `check_guard/4`-shaped helper in from a sibling chain without a real
    # CHECK to guard would be dead code at best and a silent name-based
    # guard at worst — assert its absence directly.
    test "there is no check_guard helper — this chain has no CHECK constraints to guard" do
      source = File.read!(@source)

      refute source =~ ~r/defp\s+check_guard/,
             "#{@source} defines a check_guard helper, but the moduledoc documents " <>
               "that neither table has a CHECK constraint — either a real CHECK was " <>
               "added (update the moduledoc and this test) or this is dead code " <>
               "copied from a sibling chain"

      refute source =~ ~r/contype = 'c'/,
             "#{@source} guards a CHECK constraint (contype = 'c'), but neither table " <>
               "is documented to have one"
    end

    # Every guard in this file is semantic (keyed off `contype`/`indrelid`/
    # `conrelid`/`confrelid`/`indkey`/`indoption`/`indisvalid` — shape),
    # never a bare name-equality check as its ONLY match criterion (see the
    # moduledoc's "Guards are semantic, not name-based") — a name-based
    # guard already caused real duplicate-index/crash bugs on a live host
    # for a sibling module. The index guards' DROP-first pre-check is the
    # one deliberate exception: it looks a canonically named index up BY
    # NAME on purpose (to find and repair an INVALID one under that exact
    # name), but it is never treated as "already satisfies the guard" — it
    # is gated on `i.indisvalid = false` and only ever triggers a DROP, and
    # the actual "does a matching object already exist" decision a few
    # lines below is purely shape-based, with no name comparison in it at
    # all. Each guarded `DO $$ ... $$` block is already its own element of
    # `up_statements/2`'s return list (not re-parsed out of raw source
    # text, which would need to track nested parens correctly), so this
    # asserts directly over that list.
    test "every DO-block guard's EXISTENCE check is semantic (shape-based), never name-equality alone" do
      do_blocks =
        Migrations.up_statements("public", 1)
        |> Enum.filter(&String.starts_with?(&1, "DO $$"))

      # 2 pkeys + 1 unique constraint + 3 indexes + 1 fk.
      assert length(do_blocks) == 7

      for block <- do_blocks do
        refute block =~ ~r/WHERE\s+conname\s*=\s*'[^']+'/,
               "a guard matches purely by conname — this is the exact bug class " <>
                 "documented in the moduledoc:\n#{block}"

        refute block =~ ~r/WHERE\s+indexname\s*=\s*'[^']+'/,
               "a guard matches purely by indexname — this is the exact bug class " <>
                 "documented in the moduledoc:\n#{block}"

        # The index guards' DROP-first lookup does compare `ic.relname` by
        # name — but only alongside `i.indisvalid = false`, and only to
        # decide whether to DROP, never to decide "a match already exists".
        if block =~ ~r/WHERE\s+ic\.relname\s*=/ do
          assert block =~ "i.indisvalid = false",
                 "a name-based ic.relname lookup exists without the invalid-index " <>
                   "gate that makes it safe:\n#{block}"
        end

        assert block =~ ~r/contype|indrelid|conrelid|confrelid|indkey|indoption/,
               "a guard block has no shape-based key at all:\n#{block}"
      end
    end
  end

  describe "V1 stays aligned with core's manifest (while core audits the tables)" do
    alias PhoenixKit.Migrations.ExpectedSchema
    alias PhoenixKit.Migrations.ExpectedSchema.Object
    alias PhoenixKitOG.Schemas.Assignment
    alias PhoenixKitOG.Schemas.Template

    @width_schemas %{
      "phoenix_kit_og_templates" => Template,
      "phoenix_kit_og_assignments" => Assignment
    }

    # Never a second copy of a width. Parsed back out of each CREATE rather
    # than trusted, so a hard-coded number slipped into up_statements/2
    # instead of a schema's column_widths/0 fails here even though the two
    # happen to agree today.
    test "every varchar width in each CREATE is that table's schema's column_widths/0" do
      statements = Migrations.up_statements("public", 1)

      for {table, schema} <- @width_schemas do
        columns = v1_columns(statements, table)

        parsed =
          columns
          |> Enum.filter(fn {_col, %{type: type}} -> type =~ "character varying" end)
          |> Map.new(fn {col, %{type: type}} ->
            [_, width] = Regex.run(~r/character varying\((\d+)\)/, type)
            {String.to_existing_atom(col), String.to_integer(width)}
          end)

        assert parsed == schema.column_widths(),
               """
               #{table}: the CREATE widths and #{inspect(schema)}.column_widths/0 disagree.

               parsed from DDL: #{inspect(parsed)}
               declared:        #{inspect(schema.column_widths())}
               """
      end
    end

    # Core's V154 baseline still creates both tables and core's
    # ExpectedSchema audits that shape, so until the first shape-changing
    # chain version the two DDLs must agree byte-for-byte. Bidirectional:
    # checks both that V1 creates nothing core doesn't declare AND that V1
    # is missing nothing core does declare.
    test "every column core declares matches V1's, in full, for every table" do
      statements = Migrations.up_statements("public", 1)

      for table <- @og_tables do
        core = core_columns(table)
        ours = v1_columns(statements, table)

        assert Map.keys(ours) -- Map.keys(core) == [],
               "#{table}: V1 creates columns core's manifest does not declare: " <>
                 inspect(Map.keys(ours) -- Map.keys(core))

        assert Map.keys(core) -- Map.keys(ours) == [],
               "#{table}: V1 does not create columns core's manifest declares: " <>
                 inspect(Map.keys(core) -- Map.keys(ours))

        for {column, expected} <- core do
          assert Map.fetch!(ours, column) == expected,
                 """
                 #{table}.#{column}: V1 and core's manifest disagree on the column's shape.

                 V1:              #{inspect(Map.fetch!(ours, column))}
                 core's manifest: #{inspect(expected)}

                 V1 is an adoption and must be shape-identical to core's
                 baseline. A deliberate change is a chain version (V2+).
                 """
        end
      end
    end

    # Full PK/UNIQUE/FK inventory: parses every `ADD CONSTRAINT` statement
    # V1 emits back into {table, name, kind, columns, foreign_table,
    # foreign_column, on_delete} and cross-checks each against core's
    # manifest's own structured shape for that exact constraint id
    # (`Object.newest_shape/1`) — never a hand-typed duplicate of the
    # expected shape.
    test "every PK/UNIQUE/FK constraint's columns, target, and on_delete match core's manifest" do
      statements = Migrations.up_statements("public", 1)
      manifest = ExpectedSchema.objects("public")

      constraint_statements = Enum.filter(statements, &(&1 =~ "ADD CONSTRAINT"))

      assert length(constraint_statements) == 4,
             "expected 2 pkeys + 1 unique constraint + 1 fk = 4 ADD CONSTRAINT " <>
               "statements, got #{length(constraint_statements)}"

      for stmt <- constraint_statements do
        {table, name, kind, columns, foreign_table, foreign_column, on_delete} =
          parse_constraint(stmt)

        manifest_object =
          Enum.find(manifest, &(&1.id == "constraint:#{table}.#{name}")) ||
            flunk(
              "no manifest object constraint:#{table}.#{name} — V1 emits a " <>
                "constraint core's manifest doesn't declare"
            )

        shape = Object.newest_shape(manifest_object)

        assert shape.columns == columns,
               "#{table}.#{name}: columns #{inspect(columns)} != manifest #{inspect(shape.columns)}"

        case kind do
          "FOREIGN KEY" ->
            assert shape.type == "f"
            assert shape.foreign_table == foreign_table
            assert shape.foreign_columns == [foreign_column]
            assert shape.on_delete == on_delete

          "PRIMARY KEY" ->
            assert shape.type == "p"

          "UNIQUE" ->
            assert shape.type == "u"
        end
      end
    end

    # Full index inventory: parses every `EXECUTE 'CREATE ... INDEX ...'`
    # argument V1 emits back into {name, unique, method, keys, predicate}
    # and cross-checks each against core's manifest's own structured shape —
    # columns-in-order, uniqueness, access method, and partial predicate,
    # all parsed from the real DDL text rather than hand-typed.
    test "every index's columns-in-order, uniqueness, method, and predicate match core's manifest" do
      statements = Migrations.up_statements("public", 1)
      manifest = ExpectedSchema.objects("public")

      index_statements = Enum.filter(statements, &(&1 =~ "EXECUTE '"))
      assert length(index_statements) == 3

      for stmt <- index_statements do
        {name, unique, method, keys, predicate} = parse_index(stmt)

        manifest_object =
          Enum.find(manifest, &(&1.id == "index:#{name}")) ||
            flunk(
              "no manifest object index:#{name} — V1 emits an index core's " <>
                "manifest doesn't declare"
            )

        shape = Object.newest_shape(manifest_object)

        assert unique == shape.unique, "#{name}: unique #{unique} != manifest #{shape.unique}"
        assert method == shape.method, "#{name}: method #{method} != manifest #{shape.method}"

        assert keys == shape.keys,
               "#{name}: keys #{inspect(keys)} != manifest #{inspect(shape.keys)}"

        assert predicate == shape.predicate,
               "#{name}: predicate #{inspect(predicate)} != manifest #{inspect(shape.predicate)}"
      end
    end

    defp on_delete_code("CASCADE"), do: "c"
    defp on_delete_code("SET NULL"), do: "n"
    defp on_delete_code("RESTRICT"), do: "r"
    defp on_delete_code("NO ACTION"), do: "a"
    defp on_delete_code("SET DEFAULT"), do: "d"

    defp parse_constraint(statement) do
      normalized = statement |> String.replace(~r/\s+/, " ") |> String.trim()

      regex =
        ~r/ALTER TABLE \S+\.(\w+) ADD CONSTRAINT (\w+) (PRIMARY KEY|UNIQUE|FOREIGN KEY) \(([^)]+)\)(?: REFERENCES \S+\.(\w+)\((\w+)\) ON DELETE ([A-Z ]+))?/

      case Regex.run(regex, normalized) do
        [_, table, name, kind, cols] ->
          {table, name, kind, String.split(cols, ", "), nil, nil, nil}

        [_, table, name, kind, cols, foreign_table, foreign_column, on_delete] ->
          {table, name, kind, String.split(cols, ", "), foreign_table, foreign_column,
           on_delete_code(String.trim(on_delete))}
      end
    end

    defp parse_index(statement) do
      [_, execute_sql] = Regex.run(~r/EXECUTE '([^']*)'/, statement)

      regex =
        ~r/^CREATE (UNIQUE )?INDEX IF NOT EXISTS (\w+) ON \S+ USING (\w+) \(([^)]+)\)(?: WHERE (.+))?$/

      [_, unique_flag, name, method, cols_raw | rest] = Regex.run(regex, execute_sql)

      predicate =
        case rest do
          [p] when p != "" -> p
          _ -> nil
        end

      keys = String.split(cols_raw, ", ")

      {name, unique_flag == "UNIQUE ", method, keys, predicate}
    end

    defp v1_columns(statements, table) do
      create = table_create(statements, table)

      ~r/^\s*"(\w+)"\s+(.+?),?$/m
      |> Regex.scan(create)
      |> Map.new(fn [_line, name, definition] -> {name, parse_column(definition)} end)
    end

    defp table_create(statements, table) do
      Enum.find(
        statements,
        &String.starts_with?(&1, "CREATE TABLE IF NOT EXISTS public.#{table} (")
      )
    end

    defp parse_column(definition) do
      {definition, not_null} =
        case String.replace_suffix(definition, " NOT NULL", "") do
          ^definition -> {definition, false}
          trimmed -> {trimmed, true}
        end

      case String.split(definition, " DEFAULT ", parts: 2) do
        [type] -> %{type: type, default: nil, not_null: not_null}
        [type, default] -> %{type: type, default: default, not_null: not_null}
      end
    end

    defp core_columns(table) do
      prefix = "column:#{table}."

      ExpectedSchema.objects("public")
      |> Enum.filter(&(&1.class == :column and String.starts_with?(&1.id, prefix)))
      |> Map.new(fn object ->
        {_version, shape} = List.last(object.revisions)

        {String.replace_prefix(object.id, prefix, ""),
         %{type: shape.type, default: shape.default, not_null: shape.not_null}}
      end)
    end
  end
end
