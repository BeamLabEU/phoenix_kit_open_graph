# PR #8 Review — Fix the assignment modal KeyError, and add the LiveView test plumbing

**Author:** Max Don (mdon)
**Reviewed:** 2026-08-14 (ecosystem sweep)
**Verdict:** APPROVED — merged via local conflict resolution; no post-merge code fixes needed

---

## The bug

`edit_modal/1` is a **function component**, so `@preview_loading` in its body reads *that
component's own* assigns — not the LiveView's. It was neither declared as an `attr` nor
passed at the call site, so picking a template raised `KeyError` and made the assignments
screen unusable end to end (an assignment can't be saved without choosing a template, and
choosing one is what crashed).

The PR's account of why it survived four releases is correct and worth keeping: the read
sits behind `:if={@selected_template}`, and HEEx wraps the *whole* component invocation —
attribute expressions included — in that conditional, so the modal rendered fine until a
template was picked. Nothing warns at compile time.

The fix (declare the attr, thread it from the call site) is the right one. Dropping
`loading={@preview_loading}` from `preview_panel` would also stop the crash, since the
attr defaults to `false` — but it would silently retire the preview spinner, which is why
the pass-through is correct.

---

## Merge: resolved locally, `CONFLICTING` → merged

GitHub reported this PR as `CONFLICTING`. The conflict was in
`lib/phoenix_kit_og/web/assignments_live.ex`, three hunks, and was **not** in the code
this PR changes — the branch simply predates the 2026-08-13 daisyUI 4→5 sweep:

| side | scope / group / template `<select>` |
|---|---|
| `main` | `class="select select-sm w-full"` — post-sweep |
| PR #8 | `class="select select-bordered select-sm w-full"` + `id="og-assign-*-form"` on the form |

Taking either side wholesale would have lost something real:

- taking the PR's side reintroduces `select-bordered`, a **daisyUI 4 class that matches
  nothing in v5** (v5 inputs are bordered by default) — the exact regression the
  workspace-wide sweep existed to remove;
- taking main's side drops the PR's `id` attributes, and a `phx-change` form without an
  `id` **silently disables LiveView form recovery** (core's `AGENTS.md` calls this out
  explicitly).

Resolved by taking **both**: main's daisyUI 5 classes with the PR's form `id`s. Verified
afterwards that no `select-bordered` remains anywhere in `lib/` and all three form ids are
present. Pushing the merge closed the PR as **MERGED**, not closed-unmerged.

---

## Findings

No blockers, and **no post-merge code fixes were required** — the first repo in this sweep
where that was true. `mix precommit` exits 0 and the suite is green as merged.

### The regression test is a good one, and I verified it is not vacuous

The test asserts the invariant rather than the symptom — that `edit_modal/1` reads no
assign it neither declares nor assigns in its own body — plus a separate assertion for the
call-site pass-through. That second assertion earns its place: `attr … default: false`
means a dropped pass-through would otherwise kill the spinner without failing anything.

Confirmed by removing `preview_loading={@preview_loading}` from the call site and
re-running: **2 tests, 1 failure**, naming exactly that. Restored afterwards.

Asserting against the source text rather than by rendering is a reasonable compromise here
— the module has no endpoint or router of its own, and the test says so and scopes itself
to the one component the bug was in.

### NITPICK — the new test plumbing is broader than this PR needs

`test/support/{live_case,test_endpoint,test_hooks,test_layouts,test_router}.ex` plus
`config/test.exs` changes are infrastructure, not fixes. That is a net good for a repo that
had none, and the two new LiveView tests use it — but it does mean this PR is doing two
jobs. Not worth splitting after the fact.

---

## Verification

- `mix precommit` → exit 0.
- `mix test` → **114 tests, 0 failures**.
- Dependencies updated: `phoenix_kit` 2.3.0 → 2.4.0. Nothing here calls `put_slug/3`, so
  the `~> 2.0` pin is unchanged and correct.
- Reminder for future greps: this directory is `phoenix_kit_open_graph`, but the OTP app
  and **Hex package are `phoenix_kit_og`**.
