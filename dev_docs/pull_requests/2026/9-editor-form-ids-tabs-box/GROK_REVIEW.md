# Grok Review — PR #9 "Give every editor phx-change form an id, and fix the daisyUI tabs class"

**Merge commit:** fc7a7b0
**Author:** mdon (fix/editor-form-ids-and-daisyui-tabs)
**Files:** `lib/phoenix_kit_og/web/editor_live/template.ex`

## Summary of the change

Two things:

1. daisyUI 4 `tabs-boxed` → v5 `tabs-box` on every segmented control in
   the OG editor. These stay **out** of core's `<.nav_tabs>`: they are
   radio inputs inside a `phx-change` form, so they want `role="radiogroup"`
   and form plumbing, not `role="tab"`. Agreed — same boundary core #744
   recorded.

2. Every `phx-change` form in the editor gets an `id`. A `phx-change` form
   without one silently disables LiveView form recovery; 0.3.3 already
   fixed the three scope/group/template forms for that, and this extends
   it to the editor canvas.

## Findings

### 1. NITPICK — two canvas form ids named for the wrong field

`id="og-canvas-size-form"` wrapped `name="field" value="bg_type"` (color /
image / gradient), and `id="og-canvas-bg-type-form"` wrapped
`bg_image_fit`. The button style strip was `og-button-align-form` while
the field is `preset`. LiveView recovery keys on `id`, so a misleading
name is not a functional bug, but it is the first thing a later edit
will grep for. **Fixed:** `og-canvas-bg-type-form`, `og-canvas-bg-fit-form`,
`og-button-preset-form-{id}`. Also dropped the unnecessary `#{}` around
the static gradient-dir id.

No remaining `phx-change` form in this file lacks an `id`, and no
`tabs-boxed` remains.
