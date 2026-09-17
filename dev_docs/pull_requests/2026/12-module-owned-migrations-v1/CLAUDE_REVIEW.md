# Claude Review — PR #12 "Add a module-owned V1 migration chain for the 2 og tables"

**Merge commit:** 055d074
**Author:** timujinne (feature/module-owned-migrations-v1)
**Files:** `lib/phoenix_kit_og/migrations.ex`, `lib/phoenix_kit_og.ex`,
both schemas (`column_widths/0`), `test/test_helper.exs`,
`test/phoenix_kit_og/migrations_*.exs`, `AGENTS.md`, `README.md`

## Summary of the change

`migration_module/0` now returns `PhoenixKitOG.Migrations`, a V1 chain
that adopts the two tables core's V154 still creates. V1 changes no
shape: `CREATE TABLE IF NOT EXISTS` plus semantic (catalog-shape, not
name-based) guards for PKs, the name UNIQUE constraint, the FK and the 3
indexes, an invalid-index DROP-first self-heal, and a `pkog_schema:1`
marker comment on `phoenix_kit_og_templates`. `down/1` only touches the
marker, for any target.

Checked against the resolved core (`phoenix_kit` 2.28.1):

- `PhoenixKit.Migrations.Modules` calls `migrated_version_runtime(prefix:)`
  and `current_version/0`; `mix phoenix_kit.update` generates
  `up(prefix:, version: target)` / `down(prefix:, version: installed)`.
  The coordinator matches that protocol.
- Every `Helpers` call used (`ensure_extension!/1`,
  `ensure_uuid_v7_function/1`, `uuid_v7_call/1`, `qualify_table/2`,
  `public_prefix?/1`, `validate_prefix!/1`) exists with the arity used.
- On an existing host the updater reports installed `0` → generates a
  V0→V1 file whose DDL is all no-ops except the marker. On a fresh host
  where the module file runs before core's V154, V1 creates the tables
  under core's names and V154's own `IF NOT EXISTS` guards no-op. Both
  orderings are safe.

## Findings

### 1. BUG - MEDIUM — invalid-index tests fail for a non-superuser test role

`migrations_invalid_index_test.exs` simulates a crashed
`CREATE INDEX CONCURRENTLY` with `UPDATE pg_index SET indisvalid = false`.
Writing to `pg_index` requires superuser; under a normal role (this
environment's `PGUSER`) all 3 tests fail with
`42501 permission denied for table pg_index`, turning `mix test` red on
any non-superuser CI/dev database. A real crashed `CONCURRENTLY` build
cannot be produced instead: it can't run inside the sandbox transaction.

**Fixed:** `test_helper.exs` reads `rolsuper` for `current_user` and
excludes `:requires_superuser` when false; the file carries
`@moduletag :requires_superuser`. AGENTS.md Testing notes the tag.
Superuser environments still run it.

### 2. NITPICK — environment-specific path in the moduledoc

The moduledoc cited `/app/CHANGELOG.md` (an authoring environment's
checkout path). **Fixed:** now "core's `CHANGELOG.md`".

### 3. NITPICK — moduledoc carries process narrative (not fixed)

The moduledoc describes how the research was done ("a dedicated research
pass", "adversarially re-verified by a second agent") and cross-repo
incidents. That belongs in the PR record, not API docs, and it will age.
Left as is: trimming ~160 lines of prose is churn with no behavioural
effect, and the ownership/phase sections are genuinely useful to the next
editor.

### 4. NITPICK — FK guard ignores `ON DELETE` (not fixed, by design)

A host whose existing FK has a different referential action keeps it.
Documented in the code as adoption-not-repair; agreed.

## Verification

- `mix test`: 163 tests, 0 failures, 3 excluded (superuser-only) with the
  non-superuser role.
- `mix precommit` clean.
