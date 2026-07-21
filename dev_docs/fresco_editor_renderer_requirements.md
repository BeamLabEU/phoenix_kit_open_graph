# Fresco as the OG editor + renderer — requirements & feature list

**Status:** discussion basis for the fresco/etcher maintainer. Nothing in
the og module is coupled to this yet.
**Date:** 2026-07-21

## Context

`phoenix_kit_og` today renders OG cards in a three-step pipeline: a
template's **canvas JSON** (source of truth) → `Render.Svg` generates an
SVG string per render → a rasterizer (resvg NIF, with CLI fallbacks)
produces the PNG that crawlers fetch. The editor is a *second*,
hand-written view of the same canvas JSON (browser-side SVG with
`<foreignObject>` text layout), which means editor and renderer can
disagree at the margins — most visibly on where text wraps, since the
editor uses the browser's text engine and the renderer re-implements
word-wrap by estimation.

The proposal on the table: **fresco owns both the editing stage and a
server-side renderer for the same scene model.** That closes the parity
gap for good — what the author sees is byte-for-byte what crawlers get —
and lets og delete `Render.Svg` + `Render.Rasterizer` + the placeholder
plumbing, keeping only its domain layer (templates, assignments, slot
wiring, the `refine_og/4` seam, caching/serving).

This doc lists (A) the hard requirements a fresco renderer must meet to
carry og's production path, (B) the scene-model features og needs —
these were next on og's own roadmap, so the scene model should support
them from day one, (C) og-side editor UX planned on top, which shapes
the component API, and (D) what stays og's either way.

A render-only swap (og keeps its editor, fresco only rasterizes) is
**not** worth doing — the value is one shared scene model for both.

---

## A. Renderer requirements (the bar)

The OG render path is public-production: it runs on crawler requests
against user-authored content, with no browser and no human present.

- **A1 — Text is the product.** OG cards are text-first (post titles),
  not shapes-on-photos. Required: multi-line word wrap, font weights,
  per-element font selection with a server fallback chain that works on
  a bare Debian box (DejaVu Sans / Liberation Sans / Arial), and a text
  **measurement API** (B2/B3 below depend on it). The layout the server
  computes must match what the editor displayed — this parity is the
  headline reason to adopt a shared engine at all.
- **A2 — Dynamic values at render time.** A scene is a *template*; the
  actual title/image/locale are substituted per post when the crawler
  hits. Required: `render(scene, values, opts)`-shaped API. og keeps its
  `{{slot}}` / `[[global]]` resolution and hands fresco the resolved
  values.
- **A3 — Determinism + pipeline versioning.** og caches PNGs keyed by a
  hash of the inputs; same scene + values must produce stable output,
  and the renderer must expose a version og can fold into cache keys so
  stale renders die on upgrade. (Hard-won lesson: a host served cached
  broken renders until the key learned a `render_version`.)
- **A4 — Never-crash contract + input hardening.** Scene fields are
  stored user content (free JSONB). Required: dimension clamps (a
  crafted width/height must not OOM the BEAM), untrusted-string safety
  (no markup injection through any text/color/id field), and errors
  returned, never raised — og degrades every failure to a pass-through
  (publishing's featured image), and a public post render must never
  500 because of an OG template.
- **A5 — Declare the rasterization backend early.** Something still
  turns the scene into pixels. "resvg/tiny-skia underneath" is fine (og
  simply centralizes its current dependency into fresco). A headless
  browser is **not** fine for this path — host burden and
  non-determinism both fail the bar.
- **A6 — Output contract.** PNG bytes plus declared pixel width/height
  (og emits `og:image:width/height` hints that Telegram/Facebook use to
  pre-size preview cards). Budget ~50 ms per cache-miss render at
  1200×630.
- **A7 — Font reality on bare hosts.** No bundled-font assumption:
  resolution must degrade to whatever the host has (see A1's chain) and
  do so consistently between preview and production render.

---

## B. Scene-model features og needs

These were next on og's own editor roadmap — listed here so the scene
model expresses them natively rather than og bolting them on.

- **B1 — Gradients, everywhere a fill goes.** Linear gradients (angle,
  multi-stop, per-stop alpha) usable as: a background fill, a rect/
  button fill, and — the key case — an **overlay/mask on images**, so a
  card can be half photo fading into a solid field that carries the
  text (photo → transparent-to-dark gradient → text sits on the dark
  half). Editor needs stop/angle controls; renderer must match
  pixel-for-pixel. (SVG expresses all of this natively today —
  `linearGradient` + mask — so this is table stakes for the scene
  model, not an exotic ask.)
- **B2 — Call-to-action / button element.** A first-class composite:
  pill/rect + label with padding, style presets (solid / outline / soft
  / with shadow), corner radius, and **auto-width from the label's
  measured text**. The label is a *translatable, per-language value*
  resolved at render time — an English post renders "Download", a
  French post its translation — so button geometry depends on A1's text
  measurement ("Télécharger" is wider than "Download"). A fixed-width
  button that clips translations fails the feature.
- **B3 — Anchored / linked elements.** Element B anchored to element A
  (below/above/left/right + gap + alignment): a CTA button anchored
  under the title **moves down when the title wraps to two lines** and
  back up when it fits on one. Requirements: the anchor layout must be
  computed identically in the editor and the server render (one more
  reason for one engine); anchor cycles rejected at authoring time;
  chains (C anchored to B anchored to A) should work.
- **B4 — First-class "unresolved image" placeholder state.** When a
  dynamic image slot has no value (every editor preview before wiring),
  the renderer must draw a neutral stand-in — and it must render
  **identically on every backend**. Hard-won lesson from og: shipping
  the stand-in as a nested `data:image/svg+xml` `<image>` black-squared
  on CLI backends and font-starved its caption even under resvg; og now
  inlines it as native shapes. Prefer a placeholder *state* in the
  scene model over embedded artwork.
- **B5 — Locale as a first-class render input.** The language rides
  with the values (B2 labels, any translatable text) and may affect
  layout; two locales of the same post are two distinct, cacheable
  renders.

---

## C. og-side editor UX planned on top (API context)

These stay og's to build, but they shape what the fresco components
must expose.

- **C1 — Always-on preview, platform tabs.** The current
  preview-button-with-popup goes away: the rendered preview becomes a
  **permanent pane** (author can toggle it off), with the per-platform
  social-card mockups (Telegram / Facebook / X / LinkedIn) as **tabs**.
  Implication: re-renders must be cheap and debounced/incremental — or
  the fresco stage itself is the preview (the WYSIWYG ideal), with
  platform tabs just framing it at platform aspect ratios.
- **C2 — Sectioned, tabbed controls.** The properties panel gets
  clearly labeled sections ("Background", "Element", …), and
  type-choices become **tabs instead of selects** (Background: Image |
  Solid color | Gradient). Implication for the scene model: switching a
  fill type must not destroy the other type's stored values (flipping
  Image → Gradient → back keeps the image).

---

## D. Integration seam — what stays og's

- og keeps: templates + assignments + the resolution hierarchy, slot
  wiring UI, `{{slot}}`/`[[global]]` value resolution, the
  `refine_og/4` consumer seam and its pass-through-on-error contract,
  PNG caching + `/og-image/:key` serving, activity logging.
- og deletes on adoption: `Render.Svg`, `Render.Rasterizer`,
  `Render.Placeholder` (superseded by B4).
- Migration: existing canvas JSON templates convert to the scene model
  in a one-shot, reversible pass; the cache `render_version` bumps.
- Sequencing: the **editor viewport can adopt fresco first** (pan/zoom
  is a standalone win, no production-render coupling); the render swap
  is gated on Section A. Not needed for og: deep-zoom/tessera on the
  render path, `scroll_strip`.
