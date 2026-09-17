defmodule PhoenixKitOG.Migrations do
  @moduledoc """
  Module-owned versioned migrations for `phoenix_kit_og` — the
  decentralized-migrations protocol that core's `mix phoenix_kit.update`
  discovers via `migration_module/0`. This follows the canonical shape
  documented in `phoenix_kit_hello_world`'s README ("Versioned migrations",
  "Adopting a table core already creates") and its
  `mix phoenix_kit_hello_world.audit_migrations` task: **two readers**
  (`migrated_version/1` for migration context, `migrated_version_runtime/1`
  for Mix-task context), `up/1` re-reading the version before it changes
  anything, and a namespaced `COMMENT ON TABLE` marker on one anchor table.
  `PhoenixKitPublishing.Migrations` is this chain's closest sibling in
  spirit — same adoption situation, same semantic-guard requirement —
  scaled down here to 2 tables, 1 FK, 1 named UNIQUE constraint and 3
  indexes (all on the same table), and extended with a new invalid-index
  self-heal no sibling chain in this workspace has needed yet.

  ## Ownership situation — read before touching

  Both tables are core's baseline today, created inline by core migration
  `V154` (shipped in core `1.7.206`, per core's `CHANGELOG.md`). Core's
  `ExpectedSchema` manifest carries every column of both tables, and no
  later core migration (checked through the newest entries, well past
  `V190`) ever touches either one again — `V154`'s shape is still exactly
  what a fresh install gets today. This module never shipped a migration
  file of its own before this one (`git log --all -- '*migration*'` in this
  repo confirms it), so there is no module-side predecessor whose shape
  could have been squashed incorrectly.

  A dedicated research pass — core's literal `V154` migration source,
  core's structured `ExpectedSchema.objects/1` manifest, and a live,
  fully-migrated Postgres catalog (this repo's own `phoenix_kit_og_test`,
  migrated to core's current head) — found all three in agreement,
  column-for-column, index-for-index, constraint-for-constraint, for the
  shape of both tables. That research pass was then adversarially
  re-verified by a second agent: isolated Postgres schemas built from the
  candidate DDL, diffed against a schema built from core's literal `V154`
  text, guards round-tripped twice for idempotence. Verdict: exact match,
  zero findings, idempotent. `up_statements/2` is therefore `CREATE TABLE IF
  NOT EXISTS` (full final shape) + a safety-net `ADD COLUMN IF NOT EXISTS`
  (core's own belt-and-suspenders for `slot_mapping`, kept here for the same
  reason core keeps it — an install whose `phoenix_kit_og_assignments`
  predates that column) + semantically-guarded PKs, 1 named UNIQUE
  constraint, 3 indexes, and 1 foreign key, plus the version-marker
  `COMMENT`. No `CHECK` constraint exists on either table (same three-source
  pass), so there is no `check_guard` helper in this file.

  ### Guards are semantic, not name-based — a real host discovery

  A host-level rename bug already hit this exact family of guards on a real
  install (`decor_3d_print`'s `phoenix_kit_posts` table ended up with 3
  duplicate UNIQUE indexes from a name-based guard after a host-level
  rename), and `PhoenixKitNewsletters.Migrations`' first cut crashed
  outright on a renamed host with `42P16 multiple primary keys` for the same
  reason. `ALTER TABLE ... RENAME TO` never renames a table's own
  constraints or indexes, and core's own `V154` guards get away with by-name
  checks only because the baseline runs solely on an empty database; an
  adoption chain runs on tables with an arbitrary naming history. Every
  guard here is therefore **semantic**:

    * **Primary keys** (both tables) — "does this table already have ANY
      primary key" via `contype = 'p'` on the table (resolved through
      `regclass`, immune to renames), never a check for a specific
      `<table>_pkey` name.
    * **The 1 named UNIQUE constraint** (`phoenix_kit_og_templates_name_uniq`)
      — via `contype = 'u'` PLUS the exact column set (`conkey` resolved to
      column names through `pg_attribute`), not by name.
    * **The 1 foreign key** — by source table, target table, and source
      column (all via `regclass`/`pg_attribute`, immune to renames on either
      end). The referential action (`ON DELETE ...`) is deliberately NOT
      part of the match — this is an ADOPTION guard, not a shape-repair
      tool; a host whose existing FK already disagrees on `ON DELETE` is a
      legitimate V2+ shape change, not something V1's adoption should
      silently override.
    * **The 3 indexes** — by ordered column list, uniqueness, access method
      (`btree` for all 3), and canonical partial predicate via
      `pg_get_expr`, with `indexprs IS NULL` and a column-count check so an
      expression index can never masquerade as a match. A bare `CREATE INDEX
      IF NOT EXISTS <name> ...` is not enough — it only guards its own
      literal name, not a second, differently-named index with an identical
      definition (the `phoenix_kit_posts` incident above), so every `CREATE
      INDEX`/`CREATE UNIQUE INDEX` here still runs inside a `DO $$ ... $$`
      guard via `EXECUTE`.

  ### Invalid-index handling — new to this migration-porting series

  `index_guard/8`'s semantic check requires `i.indisvalid` — an invalid
  index (left behind by a crashed `CREATE INDEX CONCURRENTLY`, which never
  happens in this chain's own DDL but can exist on a host from unrelated
  tooling) never counts as "already satisfies the guard", even under a
  different name. `indisready` is deliberately not consulted: Postgres
  clears `indisvalid` on (or before) every crashed-`CONCURRENTLY` path that
  clears `indisready`, so `indisvalid` alone covers the reachable states.
  But a bare `CREATE INDEX IF NOT EXISTS <name>` is a no-op
  against ANY existing object of that name — including an INVALID one under
  the CANONICAL name — so without an extra step, an invalid canonically
  named index would stay broken forever: the semantic check (correctly)
  says "no valid match exists" and queues a `CREATE INDEX IF NOT EXISTS`,
  which then (incorrectly) no-ops against the invalid object sharing that
  exact name. Each index guard therefore runs a DROP-first pass: if an
  index named exactly like the canonical name exists on this table and is
  invalid, it is dropped before the semantic check runs, so the subsequent
  `CREATE INDEX IF NOT EXISTS` actually creates a fresh, valid one. Verified
  live (`migrations_invalid_index_test.exs`): a plain index and a partial
  UNIQUE index each recover from a simulated crashed-`CONCURRENTLY` state
  with no duplicate left behind, idempotently. No sibling chain in this
  workspace has this yet (`grep -rl indisvalid` across the `phoenix_kit_*`
  siblings returns nothing) — this is new.

  ### Phase 0 — this V1 adopts, and changes NOTHING

  `CREATE TABLE IF NOT EXISTS` shape-identical to core's `V154` baseline,
  under core's exact object names, then a **namespaced** marker stamp on
  the anchor table (`pkog_schema:1` — an adopted table may already carry a
  foreign comment, so the reader must treat prose as version 0, never crash
  on it, never assume it means V1). Because the shape is unchanged, core's
  `ExpectedSchema` manifest stays accurate for every column of both tables:
  **no core release is required and there is no release-ordering hazard.**
  This package releases alone.

  ### Phase 1 — the first real shape change (V2+) is when core must move too

  Before shipping a version that changes either table's shape:

    1. add the objects that version alters to core's manifest generator's
       `@excluded_exact` (`dev_docs/squash/generate_baseline.exs`) and
       regenerate `ExpectedSchema`;
    2. raise this package's `:phoenix_kit` floor to the release that ships
       that regenerated manifest.

  Skipping step 1 means `mix phoenix_kit.repair` restores the old shape
  after every run, silently undoing the new version.

  ### Phase 2 — creation leaves core's baseline at the next squash cycle

  When core cuts its next baseline, module-owned tables are simply not
  included: fresh installs from then on get both `phoenix_kit_og_*` tables
  from THIS chain's V1 — which is why V1's `up/1` ensures the
  `uuid_generate_v7()` function (and its `pgcrypto` extension) exist rather
  than assuming core's chain already provided them, and why the `CREATE
  TABLE` statements here are already the full, correct definitions on their
  own, not merely shape-matching no-ops for already-existing tables.
  Existing installs are untouched — a baseline squash only affects fresh
  installs and below-floor bridging.

  ## What must NEVER happen

  No conditional core migration of the form "module absent → drop the
  tables" — that is nondeterministic (depends on which packages are
  compiled in) and destroys data on a host that merely removed the package.
  Removing this module's data is a human, manual step — see README.md
  "Removing this module" for the operator SQL (2 `DROP TABLE`s in
  FK-safe order). There is deliberately no automated uninstall path, and
  `down/1` NEVER drops either table for ANY target version, including `0` —
  it only unstamps (or re-stamps) the marker on the anchor table. The rows
  are every host's real OG templates and their per-scope assignments;
  rolling back this module's chain must not destroy any of them.

  The migrated version is tracked as a `pkog_schema:<N>` COMMENT on
  `phoenix_kit_og_templates` — the root of this chain's FK tree
  (`phoenix_kit_og_assignments.template_uuid` points at it, and nothing in
  this chain points OUT of it), so it is the one table whose independent
  loss would strand the other table's foreign key. A marker-less table, or
  one carrying a foreign (non-`pkog_schema:`) comment, reads as version 0 —
  the core-baseline shape before this chain existed.
  """

  use Ecto.Migration

  alias PhoenixKit.Migrations.Postgres.Helpers
  alias PhoenixKitOG.Schemas.Assignment
  alias PhoenixKitOG.Schemas.Template

  @initial_version 1
  @current_version 1
  @default_prefix "public"
  @marker_prefix "pkog_schema:"

  @templates "phoenix_kit_og_templates"
  @assignments "phoenix_kit_og_assignments"

  # The single table this chain's marker lives on — this chain's FK-tree
  # root, not a leaf table (see the moduledoc for why).
  @version_table @templates

  @doc "The version this code expects the schema to be at."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  The version a bare, freshly-created set of tables is at (Phase 2 — a
  future install whose core baseline no longer creates these tables).
  """
  @spec initial_version() :: pos_integer()
  def initial_version, do: @initial_version

  @doc """
  The table carrying the `pkog_schema:<N>` marker for the 2-table chain.

  Not part of the protocol `mix phoenix_kit.update` calls. Exported so an
  auditor (`mix phoenix_kit_hello_world.audit_migrations`) can verify the
  marker is really a number without hard-coding this table's name.
  """
  @spec version_table() :: String.t()
  def version_table, do: @version_table

  @doc """
  Applies every chain version up to `opts[:version]` (default
  `current_version/0`). Migration-context only — re-reads the installed
  version via `migrated_version/1` before making any change, so a database
  already at (or ahead of) the target does nothing.
  """
  @spec up(keyword() | map()) :: :ok
  def up(opts \\ []) do
    opts = with_defaults(opts, @current_version)

    if migrated_version(opts) < opts.version do
      # Don't assume core's chain ran first (Phase 2): `uuid_generate_v7()`
      # is built on pgcrypto's `gen_random_bytes`, and
      # `ensure_uuid_v7_function/1` does not install extensions — without
      # this call the function is created and then fails on the first
      # insert.
      Helpers.ensure_extension!("pgcrypto")
      Helpers.ensure_uuid_v7_function(opts.prefix)

      opts.prefix
      |> up_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  Rolls back to `opts[:version]` (default `0`). Migration-context only.
  Never drops a table or a row in either of the 2, for any target — see the
  moduledoc.
  """
  @spec down(keyword() | map()) :: :ok
  def down(opts \\ []) do
    opts = with_defaults(opts, 0)

    if migrated_version(opts) > opts.version do
      opts.prefix
      |> down_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  The version currently installed, read INSIDE a migration — through
  `Ecto.Migration`'s own `repo()`. No rescue: inside a migration a version
  that cannot be read must abort the transaction, never be guessed at.
  `up/1` and `down/1` call this — never `migrated_version_runtime/1` —
  before making any change.
  """
  @spec migrated_version(keyword() | map()) :: non_neg_integer()
  def migrated_version(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(repo(), opts.prefix)
  end

  @doc """
  Runtime-safe reader — the one `mix phoenix_kit.update` calls, from a Mix
  task with no migrator running, through PhoenixKit's configured repo
  instead of `Ecto.Migration`'s.

  An invalid prefix is re-raised, matching core's own reader: `0` means
  "not installed here", so reporting it for a bad prefix would tell the
  operator something false and send the updater off to install a schema
  over live data. Genuine unreachability still yields `0`, which is safe
  only because `up/1` re-reads the version in migration context before
  touching anything — a wrong `0` costs a redundant migration file, never
  wrong DDL.
  """
  @spec migrated_version_runtime(keyword() | map()) :: non_neg_integer()
  def migrated_version_runtime(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(PhoenixKit.RepoHelper.repo(), opts.prefix)
  rescue
    e in ArgumentError -> reraise e, __STACKTRACE__
    _ -> 0
  end

  @doc """
  The SQL `up/1` executes, as data — the testable single source. The test
  suite parses these statements to prove that the object names are core's
  `V154` names, that the `CREATE TABLE` stays shape-identical to core's
  `ExpectedSchema` manifest, that every varchar width is its owning
  schema's `column_widths/0`, and that nothing here can drop a table.

  `target` selects how much of the chain to emit (default
  `current_version/0`): `0` applies nothing (not an operation — clearing
  the marker is `down/1`'s job); `1` is the pure adoption step across both
  tables.
  """
  @spec up_statements(String.t(), non_neg_integer()) :: [String.t()]
  def up_statements(prefix \\ @default_prefix, target \\ @current_version)

  def up_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)

    if target == 0 do
      []
    else
      v1_statements(prefix, target)
    end
  end

  @doc """
  The SQL `down/1` executes, as data (marker bookkeeping only, on the
  anchor table). V1 changes no shape of its own — it is pure adoption — so
  there is nothing to drop beyond the marker; both tables and every row in
  them are left untouched, for any target including `0`.
  """
  @spec down_statements(String.t(), non_neg_integer()) :: [String.t()]
  def down_statements(prefix \\ @default_prefix, target \\ 0)

  def down_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)
    qualified = Helpers.qualify_table(@version_table, prefix)

    if target > 0 do
      ["COMMENT ON TABLE #{qualified} IS '#{@marker_prefix}#{target}'"]
    else
      ["COMMENT ON TABLE #{qualified} IS NULL"]
    end
  end

  # ── V1 statement builder ────────────────────────────────────────────────

  defp v1_statements(prefix, target) do
    uuid_default = Helpers.uuid_v7_call(prefix)

    q_templates = Helpers.qualify_table(@templates, prefix)
    q_assignments = Helpers.qualify_table(@assignments, prefix)

    tw = Template.column_widths()
    aw = Assignment.column_widths()

    # Creation order follows the FK dependency tree: templates has no FK of
    # its own, assignments points at it.
    tables = [
      """
      CREATE TABLE IF NOT EXISTS #{q_templates} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "name" character varying(#{tw.name}) NOT NULL,
        "description" character varying(#{tw.description}),
        "canvas" jsonb DEFAULT '{}'::jsonb NOT NULL,
        "preview_image_uuid" uuid,
        "inserted_at" timestamp with time zone DEFAULT now() NOT NULL,
        "updated_at" timestamp with time zone DEFAULT now() NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_assignments} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "module_key" character varying(#{aw.module_key}) NOT NULL,
        "scope_type" character varying(#{aw.scope_type}) NOT NULL,
        "scope_uuid" uuid,
        "template_uuid" uuid NOT NULL,
        "slot_mapping" jsonb DEFAULT '{}'::jsonb NOT NULL,
        "inserted_at" timestamp with time zone DEFAULT now() NOT NULL,
        "updated_at" timestamp with time zone DEFAULT now() NOT NULL
      )
      """
    ]

    # Core's own V154 carries this same safety-net ALTER right after its
    # CREATE TABLE, for installs whose table predates the `slot_mapping`
    # column — a no-op today since the CREATE TABLE above already declares
    # it, kept for the same reason core keeps it.
    safety_net = [
      "ALTER TABLE #{q_assignments} ADD COLUMN IF NOT EXISTS slot_mapping JSONB NOT NULL DEFAULT '{}'"
    ]

    pkeys = [
      pkey_guard(@templates, q_templates, ["uuid"]),
      pkey_guard(@assignments, q_assignments, ["uuid"])
    ]

    unique_constraints = [
      unique_constraint_guard(q_templates, "phoenix_kit_og_templates_name_uniq", ["name"])
    ]

    # No CHECK constraint exists on either table — confirmed by the
    # three-source research pass documented in the moduledoc.

    indexes = [
      index_guard(
        "idx_og_assignments_unique_scoped",
        q_assignments,
        true,
        "btree",
        ["module_key", "scope_type", "scope_uuid"],
        [:asc, :asc, :asc],
        "(scope_uuid IS NOT NULL)",
        prefix
      ),
      index_guard(
        "idx_og_assignments_unique_default",
        q_assignments,
        true,
        "btree",
        ["module_key", "scope_type"],
        [:asc, :asc],
        "(scope_uuid IS NULL)",
        prefix
      ),
      index_guard(
        "idx_og_assignments_template",
        q_assignments,
        false,
        "btree",
        ["template_uuid"],
        [:asc],
        nil,
        prefix
      )
    ]

    fks = [
      fk_guard(
        q_assignments,
        "phoenix_kit_og_assignments_template_uuid_fkey",
        "template_uuid",
        q_templates,
        "CASCADE"
      )
    ]

    marker = ["COMMENT ON TABLE #{q_templates} IS '#{@marker_prefix}#{target}'"]

    tables ++ safety_net ++ pkeys ++ unique_constraints ++ indexes ++ fks ++ marker
  end

  # Semantic: "does this table already have ANY primary key", not "does a
  # constraint with this exact name exist" — a table whose PK predates a
  # host-level table rename (renaming a table never renames its own
  # constraints) still has a real, functioning primary key under its old
  # name, and adding a second one is a hard Postgres error, not a silent
  # duplicate. `regclass` resolves `qualified` by the table's CURRENT name
  # regardless of that history, since a rename never changes the OID.
  defp pkey_guard(table, qualified, columns) do
    columns_sql = Enum.join(columns, ", ")

    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = '#{qualified}'::regclass AND contype = 'p'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{table}_pkey PRIMARY KEY (#{columns_sql});
      END IF;
    END
    $$
    """
  end

  # Semantic: "does this table already have a UNIQUE constraint over exactly
  # this ordered column set", via `contype = 'u'` plus `conkey` resolved to
  # column names through `pg_attribute` (same normalization `index_guard`
  # below needs for `indkey`) — not a check for the constraint's exact name.
  # `phoenix_kit_og_templates_name_uniq` is the only UNIQUE constraint (as
  # opposed to unique INDEX) across both tables.
  defp unique_constraint_guard(qualified, constraint_name, columns) do
    columns_sql = Enum.join(columns, ", ")
    columns_array = Enum.map_join(columns, ", ", &"'#{&1}'")
    column_count = length(columns)

    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = '#{qualified}'::regclass
          AND contype = 'u'
          AND array_length(conkey, 1) = #{column_count}
          AND (
            SELECT array_agg(a.attname ORDER BY k.ord)
            FROM unnest(conkey) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_attribute a ON a.attrelid = conrelid AND a.attnum = k.attnum
          ) = ARRAY[#{columns_array}]::name[]
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{constraint_name} UNIQUE (#{columns_sql});
      END IF;
    END
    $$
    """
  end

  # Semantic: "does this table already have a foreign key from `column` to
  # `references`", matched via `conrelid`/`confrelid` (both resolved through
  # `regclass`, immune to either table having been renamed) and `conkey`
  # (the source column, by attnum — immune to the constraint's own name). A
  # name-based guard would silently ADD A DUPLICATE FK under the new name
  # next to an already-functioning, differently-named one — this is not
  # hypothetical, the same defect already left 3 duplicate UNIQUE indexes on
  # a real host for a sibling module (`phoenix_kit_posts`) before this fix.
  #
  # Deliberately NOT part of the match: `on_delete` (the referential
  # action). This is an ADOPTION guard, not a shape-repair tool — if a
  # host's existing FK (found by table/column/target alone) already has a
  # different `ON DELETE` behavior than the `on_delete` argument below would
  # create, this guard leaves it exactly as it is rather than trying to
  # converge the two. A real disagreement there would be a legitimate V2+
  # shape change (with its own manifest/floor implications, see the
  # moduledoc's Phase 1), never something V1's silent adoption should paper
  # over by dropping and re-adding someone's live constraint.
  defp fk_guard(qualified, constraint_name, column, references, on_delete) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = '#{qualified}'::regclass
          AND contype = 'f'
          AND confrelid = '#{references}'::regclass
          AND conkey = ARRAY[(
            SELECT attnum FROM pg_attribute
            WHERE attrelid = '#{qualified}'::regclass AND attname = '#{column}'
          )]::smallint[]
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{constraint_name} FOREIGN KEY (#{column}) REFERENCES #{references}(uuid) ON DELETE #{on_delete};
      END IF;
    END
    $$
    """
  end

  # Semantic: "does this table already have a VALID index on these columns,
  # in this order, with this uniqueness, this access method, this partial
  # predicate, and this per-column sort direction" — NOT merely "is there an
  # index with this exact name". A bare `CREATE INDEX IF NOT EXISTS <name>
  # ...` only guards against its own literal name; it does nothing to stop a
  # second, differently-named index with an identical definition (the
  # `phoenix_kit_posts` duplicate-index incident this guard exists to
  # prevent here). `i.indkey::int2[]` resolved to column names via
  # `pg_attribute`, in index-column order, compared against the expected
  # column list; `pg_get_expr(i.indpred, i.indrelid)` is Postgres's own
  # canonical rendering of a partial index's predicate (NULL when the index
  # isn't partial) — both sides of that comparison are verified-live text,
  # not guessed. `CREATE INDEX` goes through `EXECUTE` (with the literal's
  # quotes doubled) so the whole statement is one quoted string inside the
  # block — PL/pgSQL could run it directly, `EXECUTE` is a choice, not a
  # need.
  #
  # `i.indexprs IS NULL` and the `array_length` check below both exist for
  # the same real bug, caught by testing against a live catalog rather than
  # reading the query: an EXPRESSION index stores `0` — not a real attnum —
  # in `indkey` for its expression column. `pg_attribute` has no row for
  # attnum `0`, so the `JOIN pg_attribute` above silently DROPS that
  # position instead of erroring, shortening the aggregated column-name
  # array and making an unrelated expression index misread as a plain-column
  # match. `indexprs IS NULL` alone would already exclude every expression
  # index (none of this chain's own indexes are ever expression-based); the
  # `array_length` check is kept alongside it as an independent guard
  # against the same join silently dropping a row for any other reason.
  #
  # `directions` is a per-column `:asc`/`:desc` list, always explicit (all 3
  # of this chain's indexes are ascending-only, but the parameter stays
  # explicit rather than defaulted — one code path to keep correct rather
  # than a default that silently only covers the common case).
  #
  # `i.indisvalid` in the semantic check, and the DROP-first pass ahead of
  # it, are this guard's addition over the sibling chains' `index_guard/7`
  # — see the moduledoc's "Invalid-index handling" section for why a bare
  # `CREATE INDEX IF NOT EXISTS <name>` alone cannot recover an invalid
  # canonically named index (e.g. left behind by a crashed `CREATE INDEX
  # CONCURRENTLY`). `prefix` is needed here (not just the already-qualified
  # `qualified` table reference) to build the DROP's own qualified index
  # target and the schema-name literal `ic.relnamespace` compares against —
  # index NAMES stay bare on `CREATE`/`CREATE UNIQUE INDEX` (Postgres
  # rejects a schema-qualified name there), but `DROP INDEX` accepts, and
  # here needs, a schema-qualified one so it never depends on the
  # connection's `search_path`.
  defp index_guard(name, qualified, unique?, method, columns, directions, predicate, prefix) do
    columns_sql =
      columns
      |> Enum.zip(directions)
      |> Enum.map_join(", ", fn
        {column, :desc} -> "#{column} DESC"
        {column, :asc} -> column
      end)

    where_clause = if predicate, do: " WHERE #{predicate}", else: ""
    unique_sql = if unique?, do: "UNIQUE ", else: ""
    columns_array = Enum.map_join(columns, ", ", &"'#{&1}'")
    column_count = length(columns)

    indoption_array =
      Enum.map_join(directions, ", ", fn
        :desc -> "3"
        :asc -> "0"
      end)

    predicate_condition =
      if predicate do
        "pg_get_expr(i.indpred, i.indrelid) = '#{predicate}'"
      else
        "i.indpred IS NULL"
      end

    # The whole dynamic statement is embedded inside a single-quoted
    # `EXECUTE '...'` argument, so any single quote it contains must be
    # SQL-escaped by doubling it — none of this chain's own predicates have
    # one today, but the same rule applies here as everywhere else in this
    # file that builds a string for `EXECUTE`.
    create_index_sql =
      "CREATE #{unique_sql}INDEX IF NOT EXISTS #{name} ON #{qualified} USING #{method} (#{columns_sql})#{where_clause}"

    escaped_create_index_sql = String.replace(create_index_sql, "'", "''")

    schema_name = if Helpers.public_prefix?(prefix), do: "public", else: prefix
    qualified_index_name = Helpers.qualify_table(name, prefix)

    """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class ic ON ic.oid = i.indexrelid
        WHERE ic.relname = '#{name}'
          AND ic.relnamespace = '#{schema_name}'::regnamespace
          AND i.indrelid = '#{qualified}'::regclass
          AND i.indisvalid = false
      ) THEN
        DROP INDEX #{qualified_index_name};
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class ic ON ic.oid = i.indexrelid
        JOIN pg_am am ON am.oid = ic.relam
        WHERE i.indrelid = '#{qualified}'::regclass
          AND i.indisunique = #{unique?}
          AND i.indisvalid
          AND am.amname = '#{method}'
          AND i.indexprs IS NULL
          AND array_length(i.indkey::int2[], 1) = #{column_count}
          AND #{predicate_condition}
          AND (
            SELECT array_agg(elem ORDER BY ord)
            FROM unnest(i.indoption::int2[]) WITH ORDINALITY AS u(elem, ord)
          ) = ARRAY[#{indoption_array}]::int2[]
          AND (
            SELECT array_agg(a.attname ORDER BY k.ord)
            FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
          ) = ARRAY[#{columns_array}]::name[]
      ) THEN
        EXECUTE '#{escaped_create_index_sql}';
      END IF;
    END
    $$
    """
  end

  # ── internals ──────────────────────────────────────────────────────────

  defp with_defaults(opts, version) do
    opts = Enum.into(opts, %{})
    prefix = validated_prefix(Map.get(opts, :prefix) || @default_prefix)

    opts
    |> Map.put(:prefix, prefix)
    |> Map.put_new(:version, version)
  end

  defp read_version(repo, prefix) do
    if table_exists?(repo, prefix) do
      repo |> table_comment(prefix) |> parse_version()
    else
      0
    end
  end

  defp table_exists?(repo, prefix) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_name = $1 AND table_schema = $2
    )
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[exists?]]}} -> exists?
      {:error, error} -> raise error
    end
  end

  defp table_comment(repo, prefix) do
    query = """
    SELECT pg_catalog.obj_description(c.oid, 'pg_class')
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = $1 AND n.nspname = $2
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[comment]]}} -> comment
      {:ok, %{rows: []}} -> nil
      {:error, error} -> raise error
    end
  end

  defp parse_version(@marker_prefix <> n) do
    case Integer.parse(n) do
      {version, ""} when version >= 0 -> version
      _ -> 0
    end
  end

  defp parse_version(_), do: 0

  defp validate_target!(target) when target > @current_version do
    raise ArgumentError,
          "PhoenixKitOG.Migrations has no version #{target} " <>
            "(current_version/0 is #{@current_version}); stamping it would make every " <>
            "later version look already applied"
  end

  defp validate_target!(_target), do: :ok

  # `phoenix_kit` is a normal (non-optional) dependency of this package, so
  # `Helpers` is always loaded.
  defp validated_prefix(prefix) do
    Helpers.validate_prefix!(prefix)
    prefix
  end
end
