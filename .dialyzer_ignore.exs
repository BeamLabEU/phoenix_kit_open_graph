# Dialyzer findings deliberately not treated as errors.
#
# All of these predate the phoenix_kit 2.0 sweep. They were invisible until
# then because `mix precommit` runs `quality.ci` = format → credo → dialyzer,
# and credo had been failing first (22 findings on `main`), so dialyzer never
# ran. Clearing credo surfaced them; none is a defect.
#
# Review before adding to this list — an entry here is a claim that the finding
# is not a bug, not a way to quiet a real one.

[
  # ── Optional rasterizer backend ────────────────────────────────────────
  # `OpenFresco.render/3` is specced `{:ok, binary(), map()} | {:error, term()}`,
  # but the PNG rasterizer is an OPTIONAL backend the HOST installs
  # (`{:resvg, "~> 0.5"}`, or resvg / rsvg-convert / ImageMagick on PATH). None
  # is present in this package's own dev/CI environment, so dialyzer proves the
  # success branch unreachable *here* and, transitively, that the function
  # handling it is never called. Both come back the moment a backend exists,
  # which is the only configuration where OG rendering runs at all.
  {"lib/phoenix_kit_og/render.ex", :pattern_match},
  {"lib/phoenix_kit_og/render.ex", :unused_fun},

  # ── Defensive clauses dialyzer can prove unreachable ───────────────────
  # Each of these is a fallback kept on purpose: the type that makes it dead
  # is inferred from today's callers, and the clause is what stops a future
  # caller from turning a new shape into a crash. Removing them would trade a
  # graceful degradation for a FunctionClauseError.

  # `{_scope, nil}` in the hierarchy walk — skips an unset scope. Dead only
  # because every current caller builds the list with non-nil scope uuids.
  {"lib/phoenix_kit_og/assignments.ex", :guard_fail},

  # `truncate/1`'s short-string branch. Dialyzer infers the length test is
  # always true from `inspect/1`'s return type; the branch is still the
  # correct behaviour for a short binary.
  {"lib/phoenix_kit_og/errors.ex", :pattern_match},

  # The generic `{:error, reason}` arm after `{:error, %Ecto.Changeset{}}`.
  # Dead only while the `with` chain can fail in exactly one way.
  {"lib/phoenix_kit_og/web/assignments_live.ex", :pattern_match_cov}
]
