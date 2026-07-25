# open_fresco 0.1.0 — consolidated feedback / TODO from phoenix_kit_og

phoenix_kit_og switched to open_fresco wholesale (storage, editor stage,
renderer) and it works — verified in tests and in the browser: anchors
follow text wrap, auto-width buttons measure per label, gradient masks,
drag/select/delete on the stage, deterministic renders, clean escaping in
every context we probed. This is everything we hit or foresee, in one
list — **all of it is for the next version**. Items marked
**[verified]** were reproduced against 0.1.0 source or a live host;
**[design]** items are asks, not bugs.

---

1. **[verified] Compiles only when `phoenix_live_view` is installed.**
   The optional-dep guard around `OpenFresco.Editor` doesn't take effect
   at deps-compile time — a renderer-only host gets
   `Phoenix.LiveComponent is not loaded` and can't build. Breaks the
   "renderer without editor" story completely.

2. **[verified] Select-then-drag race in the hook.** `pointerDown`
   pushes an async `editor:select` but seeds the drag from the *previous*
   `dataset.selected`; click-and-drag in one gesture drags the wrong (or
   no) element, and the mid-drag server patch can replace the node
   carrying the local transform preview. The structural fix (consensus of
   every reviewer we ran this by): synchronous client-side hit-test at
   pointerdown (the `elementAt`/`data-uuid` walk is already in the file,
   unused), pointer capture, local optimistic preview, one revision-tagged
   commit on `pointerup`, rollback on `pointercancel`, and
   `phx-update="ignore"` scoped to the active node during the gesture.
   Server hit-test stays fine for plain clicks.

3. **[verified] Resize is advertised but not wired.** `Ops.resize/5`
   and the `editor:resize` handler exist, but the JS hook never emits
   `editor:resize` and the selection chrome has no handles. Finish
   handles + emitter — a half-advertised API is worse than a missing one.

4. **[verified] Hit-testing runs on pre-layout geometry.**
   `editor:select` calls `Ops.hit_test` against *stored* boxes, but the
   SVG paints *resolved* boxes (`Layout.resolve`: anchors, auto-width,
   place, wrap height). An anchored or auto-width element paints
   somewhere its stored box isn't — clicking where it visibly is misses
   it (or grabs a neighbor). Hit-test and drag math must consume the same
   resolved layout the paint pass used, including paint order.

5. **CLI backends have no execution timeouts.** A hung `rsvg-convert`
   or ImageMagick subprocess parks the calling process forever and leaks
   OS processes under load. Ports need kill-on-timeout guards (and
   bounded stderr collection + temp-file cleanup).

6. **External-resource fetch policy (SSRF) is undeclared.** Scene
   image values can carry `http(s):` hrefs; whatever any backend does
   with them today, the safe contract is: **no network at render time,
   ever**, unless the host installs an explicit resolver. Deny by
   default, document it, and make sure every backend (NIF + all CLIs)
   actually obeys — CLI rasterizers have their own fetch behaviors.

7. **[verified upstream] Tiny raster images render as nothing.** A
   valid 1×1 PNG data-URL paints nothing on any backend we tried —
   silently missing from the output. Likely a resvg quirk: worth an
   upstream report, and on your side a typed warning (see item 23's
   telemetry) instead of silent omission.

8. **Scene format versioning + migration + non-raising decode.** The
   serialized scene needs an explicit `schema_version`, a `migrate/1`
   upconverter pipeline, and a **non-bang** `Scene.from_map/1` returning
   `{:ok, scene} | {:error, reason}` where the reason carries the JSON
   path + element index of the offender (so admin UIs can highlight it),
   plus documented strict/lenient modes for unknown fields. Consumers
   feed DB JSONB into this — today we rescue `from_map!` and silently
   fall back to a blank scene, which loses someone's template on a
   corrupt row.

9. **Component ownership + notification contract.** Three connected
   gaps: (1) `update/2` unconditionally re-assigns `:scene` from the
   parent while the component also mutates it and notifies — a parent
   re-render can clobber an in-flight gesture; define
   controlled-vs-uncontrolled (or scene revisions with
   accept-only-if-newer). (2) `assign_new(:selected)` means the host can
   never drive selection programmatically (we want: click a slot chip →
   highlight its element). (3) `notify/2` is `send(self(), …)` — it only
   reaches the root LiveView; a host wrapping the stage in its own
   LiveComponent never sees `scene_changed`. Accept a configurable
   notify target (pid, or `{module, id}` for `send_update`).

10. **Transient-vs-commit event semantics (+ undo for free).**
    `{:scene_changed, scene}` fires per operation with no distinction
    between mid-gesture and committed states — naive hosts persist every
    drag frame. Distinguish the two, and have `Ops` return the inverse
    operation alongside each result: hosts then get undo/redo almost for
    free.

11. **A real resource-resolver contract (replaces "stage media
    hook").** We store opaque media UUIDs in scenes; the PNG path
    resolves them host-side to `data:` URLs, but the **stage** can't
    display them — authors see a stand-in where their picked image is.
    Rather than a display-URL callback, make it one contract both the
    stage and the rasterizer share: resolver returns bytes-or-URI + MIME
    + content digest + typed failure. The digest then feeds item 12.

12. **Honest cache identity: a render manifest.** Engine version alone
    understates the determinism surface — NIF vs CLI vs ImageMagick
    paint different pixels, and a system font change alters both
    measurement and paint. Expose a manifest per render (backend +
    version, measurement mode used, font-resolution digest, asset
    digests, options) so caches key on the actual pixel-producing
    inputs; and offer "hard-error instead of silently falling back to a
    different backend."

13. **Stacking API.** `bring_to_front/2` exists, `send_to_back/2`
    doesn't (we z-hack it). Generalize: `reorder(scene, id, index)` plus
    front/back/forward/backward conveniences, with deterministic paint
    order for equal `z`.

14. **Editor should accept `globals:`.** The stage renders
    `[[site_url]]` as a literal token while the PNG resolves it — pass
    globals through to the component's `render_svg` (one shared
    substitution path for stage and PNG; the divergence is the symptom).

15. **[design] Fill-variant switching: pick a side.** README says fills
    "toggle between variants without data loss", but fill maps hold only
    their own type's fields — we stash the inactive variants in LiveView
    state. Our reviewers split on the fix: make fill a tagged union that
    *retains* per-variant fields (lossless by construction) **vs** keep
    inactive variants out of the canonical scene (cache/persistence
    hygiene) and let editors hold drafts. Either is workable — but
    decide it in the schema, and correct the README meanwhile.

16. **Drag vs `place`/`anchor` semantics are undefined.** `Ops.move`
    writes absolute box coords; the next layout pass can snap an
    anchored element right back (or silently bake absolutes and break a
    responsive template). Define the edit policy: free-dragging a
    constrained element either updates the constraint's offset, or
    explicitly detaches the constraint (with the editor able to say
    which).

17. **Transform-safe pointer math, then stage fit/pan-zoom.** The hook
    converts pointer coords with `getBoundingClientRect` deltas, which
    breaks under any CSS transform, zoom, or fractional DPR — convert
    through `svg.getScreenCTM().inverse()`. Do that first; *then* give
    the stage fit-to-container scaling and (ideally) the fresco pan-zoom
    integration the package name promises — today the SVG renders 1:1 in
    a plain div and a 1200px canvas overflow-scrolls on small screens.
    Define pan-vs-select arbitration and touch/wheel behavior as part of
    it.

18. **SVG security contract beyond escaping.** We probed text,
    font-family, fill/color and background attribute contexts and found
    everything correctly escaped — good. But scene JSON is DB content
    rendered into an **admin DOM** via `raw/1`, so the safety story
    should be a *contract*, not an emergent property: a fixed
    tag/attribute/URL-scheme allowlist on generated SVG, fuzz tests over
    scene fields, a documented policy for the stage-vs-PNG capability
    divergence (browsers execute things resvg ignores), and CSP
    expectations for hosts.

19. **[verified] Per-instance namespacing of generated SVG ids.**
    `of-glow-t1` / `of-maskgrad-img0` are element-scoped, not
    instance-scoped — two stages (or any two inline renders of scenes)
    on one page cross-reference each other's `<defs>` via `url(#id)` and
    paint the wrong fills. Prefix ids with the component instance id or
    a scene hash. (Not live for us today — our preview pane is a raster
    `<img>` — but it's one "second editor on the page" away.)

20. **Don't ship the whole SVG as one `raw/1` blob.** Every change
    retransmits the entire SVG over the wire (including inlined data-URL
    images, which can be megabytes) and defeats LiveView's fine-grained
    diffing. Stable keyed nodes — or at least splitting heavy `<image>`
    hrefs from the frequently-changing geometry — would cut patch sizes
    dramatically.

21. **International text: define the boundary honestly.** Measured
    wrap currently assumes space-separated LTR text. CJK/Thai (no
    spaces), RTL/bidi, grapheme clusters (emoji ZWJ, combining marks)
    all produce wrong break points — that's breaking, not cosmetic.
    Either adopt UAX #14-aware line breaking with explicit
    `lang`/`direction` inputs, or *document* a supported-scripts matrix
    and fail loudly outside it. ("Télécharger" passing is not i18n
    readiness.)

22. **Custom/brand font loading.** resvg's fontdb supports font dirs
    and files but nothing is exposed — cards are stuck with host system
    fonts. `config :open_fresco, font_dirs: [...]` (plus the font digest
    feeding item 12, and a supervised registry so font scanning isn't
    paid per render) is probably the single highest user-visible feature
    gap: branded OG cards need brand fonts.

23. **Operational hardening + observability.** Confirm the NIF runs on
    dirty CPU schedulers; recommend a bounded concurrency pattern
    (`Task.Supervisor` + limits) for crawler-path rendering in the docs;
    add Telemetry events: render duration, backend used, backend
    fallback, estimate-vs-measured wrap, and "element painted nothing"
    (which would have surfaced item 7 in production instead of by
    eyeball). Budget total work, not just canvas dimensions:
    `:max_dimension` exists (thanks), but ten 3200×3200 data-URL images
    in one scene is the same 400MB — cap decoded-image bytes, element
    count, and scene byte size too.

24. **Measurement accuracy on CLI-only hosts.** Text measurement
    requires the resvg NIF; without it, layout falls back to character
    estimates while a CLI backend still *paints* real fonts — wrap
    points can visibly mismatch. Document it prominently, or measure via
    the CLI as well.

25. **Conformance tests as a package deliverable.** Browser tests for
    the gesture protocol (injected latency, mid-gesture patches, scaled
    stages, reconnects, nested components), and renderer fixtures with
    bundled fonts + RTL/CJK/emoji across every backend. Treat item 7 as
    a conformance case. An exported test helper for hosts (assert-on-SVG,
    snapshot diffing) would let us CI our templates against your layout.

Explicitly NOT asked for now (don't spend time on these): keyboard/ARIA
operability on the stage, multi-select/batch ops.

---

## Where phoenix_kit_og stands meanwhile (so you know the workarounds)

Already working around: LV always present (item 1 moot for us), z-hack
for send_to_back (13), globals absent on stage (14), LV-side fill stash
(15), stand-ins for media on stage (11), `max_dimension: 4000` passed
explicitly, `from_map!` rescued to a blank scene (8 — the one we most
want gone). Nothing here blocks us day-to-day; items 2 and 4 are the
ones authors will feel first.
