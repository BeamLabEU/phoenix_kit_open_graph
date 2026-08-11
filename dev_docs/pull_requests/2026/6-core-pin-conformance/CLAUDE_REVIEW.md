# PR #6 — Add a conformance test for the `:phoenix_kit` requirement

**Author:** mdon · **Branch:** `main` (fork) · **Reviewed:** 2026-08-11

One test file, no production code. Guards the core pin against being
re-narrowed to a single minor, and against a `path:` dep reaching a commit.

## Verified

The premise is correct and the workspace has the scar to prove it: `~> 2.0.x`
expands to `>= 2.0.x and < 2.1.0`, so no core 2.1 can satisfy it, and the
failure lands in the *consumer's* `mix deps.get` where this repo's own suite
never sees it. AGENTS.md records the same trap.

The dual resolution order is the part worth checking, and it is right:
`Mix.Project.config()` first, then a regex over the committed `mix.exs`
literal. The fallback exists because `pk_dep/3` rewrites the dep to a `path:`
tuple whenever `PHOENIX_KIT_PATH` is exported — the sanctioned way to run this
suite against unreleased core — so a check reading only the resolved dep would
fail that documented workflow. Confirmed `mix.exs:61` uses exactly that form
(`pk_dep(:phoenix_kit, "~> 2.0")`), and that the regex `:phoenix_kit,\s*"` can
only match the dep literal: `:phoenix_kit_og` has a different atom, and
`extra_applications: [:logger, :phoenix_kit]` is not followed by a quote.

The admit/reject vectors are the right ones, and excluding core 1.7 is
correct — this module is verified only against the V135 baseline.

No findings. Nothing changed.

## Verification

- `mix test` — 90 tests, 0 failures (17 `:integration` excluded — no
  PostgreSQL in the review environment; this test needs none and did run).
- `mix precommit` (incl. dialyzer) — clean, exit 0.
