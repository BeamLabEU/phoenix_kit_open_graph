# Fresco editor + renderer — feature checklist from phoenix_kit_og

What the OG-image module needs fresco's editor and server renderer to
be able to do before it can replace og's own canvas/SVG/rasterizer
pipeline. Each item is meant to be checkable; the ones marked **(gate)**
are hard requirements — og can't switch without them.

Background in one line: og templates are *designs with holes* — the
actual post title, image, and language get substituted per post at
render time, and the result must reach crawlers as a PNG rendered
server-side with no browser involved.

---

## 1. Scene model (shared by editor and renderer)

- [ ] **(gate)** Element types: text block, image, rect/shape, and a
      **button/CTA composite** (shape + label with padding, style
      presets solid/outline/soft, corner radius).
- [ ] **(gate)** Template values: any text or image field can be a
      placeholder resolved at render time (`render(scene, values)`),
      not baked into the scene.
- [ ] **(gate)** Fill types on any fillable element/background: solid
      color, **linear gradient** (angle, multiple stops, per-stop
      alpha), image (cover / contain / stretch fit).
- [ ] **(gate)** Gradient as **overlay/mask on images** — e.g. a photo
      fading left-to-right into a solid dark field that text sits on.
- [ ] **(gate)** **Anchored elements**: element B anchored to element A
      (above/below/left/right + gap + alignment). When A's rendered
      height changes (a title wrapping to two lines), B moves
      accordingly. Chains (C→B→A) work; cycles are rejected.
- [ ] **(gate)** A first-class **"unresolved image" placeholder state**
      that draws a neutral stand-in when an image value is missing —
      not embedded artwork. (Lesson from og: a nested
      `data:image/svg+xml` stand-in rendered as a black square on some
      rasterizer backends and lost its caption text on others.)
- [ ] **(gate)** Locale is a render input: translatable values (e.g. a
      CTA label — "Download" / "Télécharger") resolve per language, and
      two locales of one post are two distinct renders.
- [ ] Z-order control; fixed canvas dimensions (1200×630 typical).
- [ ] Switching a fill type does not destroy the other types' stored
      values (an Image | Color | Gradient tab UI must round-trip).
- [ ] Serialized format is versioned and migratable.

## 2. Editor (browser stage)

- [ ] **(gate)** Drag, resize, select on the artboard; keyboard nudge;
      delete. Pan/zoom/fit around a fixed-size artboard.
- [ ] **(gate)** Embeddable in a host LiveView that owns the properties
      panel — the host gets selection/change events and can update the
      scene programmatically (og keeps its own panel, slot wiring, and
      admin chrome).
- [ ] **(gate)** Text layout in the editor matches the server render —
      same wrap points, same measured sizes. This parity is the main
      reason to adopt a shared engine.
- [ ] Anchor authoring (pick anchor target/edge/gap visually or via
      host UI events).
- [ ] JS ships as a bundle registered on the LiveSocket (no inline
      `<script>` — must survive LiveView navigation).
- [ ] Element/DOM ids are instance-scoped (no collisions with the rest
      of the admin page).

## 3. Renderer (server-side)

- [ ] **(gate)** `render(scene, values, opts)` → `{:ok, png_binary}` |
      `{:error, term}` — returns errors, never raises; no browser, no
      network fetches at render time (image inputs arrive as
      bytes/paths).
- [ ] **(gate)** Text: multi-line word wrap, font weights, per-element
      fonts, and a fallback chain that works on a bare Linux host
      (DejaVu Sans / Liberation Sans / Arial). Text **measurement**
      drives layout (auto-width buttons, anchors).
- [ ] **(gate)** Deterministic: same scene + values → stable output,
      and the renderer exposes a **version** the caller can fold into
      cache keys so cached PNGs invalidate on upgrade.
- [ ] **(gate)** Hardened for user-authored scenes: width/height
      clamped (no OOM from a crafted canvas), all strings treated as
      untrusted (no markup/attribute injection), unknown fields
      tolerated.
- [ ] **(gate)** Embedded rasterization engine (resvg/tiny-skia class).
      A headless browser does not qualify (host burden +
      non-determinism).
- [ ] Output declares pixel width/height (needed for
      `og:image:width/height` meta hints).
- [ ] ~50 ms per render at 1200×630 on typical hardware (runs on the
      crawler request path; caller caches).
- [ ] Heavy native deps follow the optional-dependency pattern so hosts
      that only use the editor don't pay for the renderer.

## 4. What og does when this ships

og keeps its domain layer either way (template/assignment admin, the
post→group→default resolution hierarchy, slot wiring, the `refine_og/4`
consumer seam, PNG caching + serving). On a release that checks the
gates: og validates with a text-heavy real template (wrap parity,
anchors, gradients, locale), migrates stored canvases to the scene
format, swaps the editor stage and render call, and deletes its own
SVG/rasterizer/placeholder code. Until then og runs unchanged, so
nothing here blocks either side's schedule.
