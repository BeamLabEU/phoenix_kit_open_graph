# Grok Review — PR #10 "Use core nav_tabs for the preview platform switcher"

**Merge commit:** 5d8b6bb
**Author:** mdon (fix/nav-tabs-preview-switcher)
**Files:** `lib/phoenix_kit_og/web/editor_live.ex`, `lib/phoenix_kit_og/web/editor_live/template.ex`

## Summary of the change

The preview-platform strip (Card / Facebook / X / LinkedIn / Discord) is
a real event-tab strip: it switches chrome around the live stage, not a
form value. Companion to core #746. Agreed it belongs on `<.nav_tabs>`
— and agreed the nine property-panel segmented controls around it stay
hand-rolled: those are radio inputs inside `phx-change` forms, the same
boundary core #744 recorded and PR #9 kept.

Payload key moves `platform` → `tab`, matching `phx-value-tab`. The
handler already had a catch-all `set_preview_platform` clause that
returns `:noreply` for anything it doesn't recognise, so a missed key
rename would have been a silent no-op, not a crash.

This call site uses the event-tab API (`on_change` + no link keys).
That already shipped in core 2.13.5. The PR body warned CI would stay
red against Hex 2.13.5 until `variant={:border}` / verbatim `:patch`
landed in 2.13.6 — those are the *wave's* new APIs, and this strip uses
neither (boxed is the default; there is no URL). The warning is
copy-paste from the other companions, not a requirement of this patch.

## Findings

### 1. NITPICK — `p-0.5` fought boxed's baked-in `p-1`

`class="tabs-sm p-0.5"` is appended to `:boxed`'s
`tabs tabs-box bg-base-200 p-1`. Core is explicit: `class` can only
ADD, which is why `:plain` exists. Two padding utilities on one node
are resolved by stylesheet order, not HTML order, so `p-0.5` was a
no-op (and `p-1` won). **Fixed:** drop `p-0.5`, keep `tabs-sm`. Also
fed `platform_tabs/0` as maps (`%{id, label}`) instead of mapping
tuples at the call site — same shape every other event-tab strip uses.

### 2. IMPROVEMENT — no test, and the catch-all makes a mismatch silent

Nothing asserted that the template emits `phx-value-tab` or that the
handler matches `%{"tab" => _}`. Reverting only one side would compile,
the suite would stay green, and clicks would do nothing. The two id
lists (`platform_tabs/0` and `@preview_platforms`) have the same
failure mode: an id in the strip that isn't in the guard is dropped on
the floor.

**Fixed:** source-level contract in `editor_preview_tabs_test.exs`
(payload key + the two lists stay in sync) and a LiveView click in
`editor_live_test.exs` that wraps the stage in Facebook chrome, then
proves the old `%{"platform" => "discord"}` payload is a no-op.

EditorLive is now on the test router (`/:uuid/edit`). TemplatesLiveTest
deliberately stayed off MediaBrowser/OpenFresco; this path needs them,
and the mount succeeded against the existing test endpoint.

No remaining `phx-value-platform` in the editor. The constant/variable
image-source strip (the other excluded copy from core #746) is still
hand-rolled on purpose: each button has its own `phx-click` event name
via `mode_event/2`, which `nav_tabs` cannot express.
