// PhoenixKitOG editor hooks — drag/resize (PhoenixKitOGCanvas) + keyboard
// (PhoenixKitOGEditor). Shipped via `PhoenixKitOG.js_sources/0` so core's
// :phoenix_kit_js_sources compiler folds it into the host's single LiveSocket
// at construction — the ONLY registration that survives LiveView navigation
// (an inline <script> only runs on a hard load, not a morphdom patch, so the
// hook was silently absent when you nav'd into the editor from the list).
// Registered on window.PhoenixKitOGHooks, which the host spreads into hooks.

// IIFE guard: register once even if the bundle is somehow evaluated twice.
(() => {
  if (window.__pkOgEditorRegistered) return;
  window.__pkOgEditorRegistered = true;

  // Watchdog: if the hook hasn't mounted a few seconds after
  // load, reveal the warning banner. The hook clears this flag
  // by setting `data-pk-og-hook-ready="true"` on the wrapper.
  setTimeout(() => {
    const wrapper = document.getElementById("og-canvas-wrapper");
    const warn = document.getElementById("og-editor-js-warning");
    if (warn && wrapper && wrapper.dataset.pkOgHookReady !== "true") {
      warn.hidden = false;
    }
  }, 2500);

  const Hooks = (window.PhoenixKitOGHooks = window.PhoenixKitOGHooks || {});

  // Convert a client point to canvas units using the SVG's CTM.
  function clientToCanvas(svg, evt) {
    const pt = svg.createSVGPoint();
    pt.x = evt.clientX;
    pt.y = evt.clientY;
    const ctm = svg.getScreenCTM();
    if (!ctm) return { x: 0, y: 0 };
    const out = pt.matrixTransform(ctm.inverse());
    return { x: out.x, y: out.y };
  }

  // Anchor `[cx, cy]` for a resize handle given its position code
  // and the element's bounds. Mirrors the server-side layout in
  // the `selection` HEEx component so live drag matches the
  // eventual re-render.
  function handleAnchor(position, x, y, w, h) {
    switch (position) {
      case "nw": return [x, y];
      case "n":  return [x + w / 2, y];
      case "ne": return [x + w, y];
      case "e":  return [x + w, y + h / 2];
      case "se": return [x + w, y + h];
      case "s":  return [x + w / 2, y + h];
      case "sw": return [x, y + h];
      case "w":  return [x, y + h / 2];
      default:   return [x, y];
    }
  }

  Hooks.PhoenixKitOGCanvas = {
    mounted() {
      const svg = this.el;
      let drag = null;
      let resize = null;
      // Set on pointer-up if the interaction was a real
      // drag/resize; used to swallow the synthetic `click` event
      // that would otherwise bubble to `phx-click="deselect"` on
      // the SVG root and blow away the selection mid-interaction.
      let swallowNextClick = false;

      // Flip the wrapper's readiness flag so the "JS didn't
      // load" banner disappears. The banner is rendered by the
      // server (default state) and hidden by CSS when the flag
      // is `true` — so anyone stuck on a stale/failed JS bundle
      // gets a visible hint instead of a silently-dead editor.
      const wrapper = document.getElementById("og-canvas-wrapper");
      if (wrapper) wrapper.dataset.pkOgHookReady = "true";

      const onPointerDown = (evt) => {
        const dragTarget = evt.target.closest("[data-pk-og-drag-handle]");
        const resizeTarget = evt.target.closest("[data-pk-og-resize-handle]");

        if (resizeTarget) {
          evt.preventDefault();
          evt.stopPropagation();
          const id = resizeTarget.dataset.pkOgResizeHandle;
          const position = resizeTarget.dataset.position;
          const el = this.findElement(id);
          if (!el) return;
          const start = clientToCanvas(svg, evt);
          const origin = this.boundsForElement(id);
          resize = {
            id,
            position,
            start,
            origin,
            // Seed `last` with the current bounds so a zero-
            // movement pointerup sends the *current* size to the
            // server rather than reverting.
            last: { ...origin },
          };
          try { svg.setPointerCapture(evt.pointerId); } catch (_) {}
        } else if (dragTarget) {
          evt.preventDefault();
          evt.stopPropagation();
          const id = dragTarget.dataset.pkOgDragHandle;
          const start = clientToCanvas(svg, evt);
          drag = { id, start, dx: 0, dy: 0 };
          try { svg.setPointerCapture(evt.pointerId); } catch (_) {}
        }
      };

      // Capture-phase click listener on the SVG root: if the
      // pointerup just ended a drag/resize, swallow the click so
      // it doesn't fall through to `phx-click="deselect"`.
      const onClickCapture = (evt) => {
        if (swallowNextClick) {
          evt.stopPropagation();
          evt.preventDefault();
          swallowNextClick = false;
        }
      };

      const onPointerMove = (evt) => {
        if (drag) {
          const cur = clientToCanvas(svg, evt);
          drag.dx = Math.round(cur.x - drag.start.x);
          drag.dy = Math.round(cur.y - drag.start.y);
          this.applyTempTransform(drag.id, drag.dx, drag.dy);
        } else if (resize) {
          const cur = clientToCanvas(svg, evt);
          const dx = cur.x - resize.start.x;
          const dy = cur.y - resize.start.y;
          this.applyTempResize(resize, dx, dy);
        }
      };

      const releaseCapture = (evt) => {
        try {
          svg.releasePointerCapture(evt.pointerId);
        } catch (_) {
          // Capture may already be released (or never taken);
          // never let this throw and orphan the drag state.
        }
      };

      const onPointerUp = (evt) => {
        // Clear the interaction state FIRST — even if the
        // pushEvent below throws (rare, but a bad server reply
        // shouldn't leave the DOM in a "stuck" state), the local
        // vars are reset so the next pointerdown starts clean.
        const wasDrag = drag;
        const wasResize = resize;
        drag = null;
        resize = null;
        releaseCapture(evt);

        if (wasDrag) {
          if (wasDrag.dx !== 0 || wasDrag.dy !== 0) {
            swallowNextClick = true;
            // Bake the drag delta into the children's `x`/`y`
            // attributes and drop the transient `transform` in
            // the same tick. This way the DOM already matches
            // what the server will render on the ack — morphdom
            // sees no diff and there's no visual patch, which
            // eliminates the rubber-band between "transform
            // removed" and "children x/y updated".
            this.commitDragBounds(wasDrag.id, wasDrag.dx, wasDrag.dy);
            this.pushEvent("move_element", {
              id: wasDrag.id,
              dx: wasDrag.dx,
              dy: wasDrag.dy,
            });
          } else {
            this.clearTempTransform(wasDrag.id);
          }
        } else if (wasResize) {
          swallowNextClick = true;
          const rect = this.computeResizeBounds(wasResize);
          this.pushEvent(
            "resize_element",
            {
              id: wasResize.id,
              x: Math.round(rect.x),
              y: Math.round(rect.y),
              width: Math.round(rect.width),
              height: Math.round(rect.height),
            },
            () => this.clearTempResize(wasResize.id)
          );
        }
      };

      svg.addEventListener("pointerdown", onPointerDown);
      svg.addEventListener("pointermove", onPointerMove);
      svg.addEventListener("pointerup", onPointerUp);
      svg.addEventListener("pointercancel", onPointerUp);
      // Capture-phase so the listener runs *before* LV's own
      // `phx-click` handler on the same element.
      svg.addEventListener("click", onClickCapture, true);

      this._cleanup = () => {
        svg.removeEventListener("pointerdown", onPointerDown);
        svg.removeEventListener("pointermove", onPointerMove);
        svg.removeEventListener("pointerup", onPointerUp);
        svg.removeEventListener("pointercancel", onPointerUp);
        svg.removeEventListener("click", onClickCapture, true);
      };
    },

    destroyed() {
      this._cleanup && this._cleanup();
    },

    findElement(id) {
      return this.el.querySelector(`[data-pk-og-element="${id}"]`);
    },

    boundsForElement(id) {
      const g = this.findElement(id);
      if (!g) return null;
      // First DIRECT child that's sized — restricting to direct
      // children skips descendants that live inside <pattern>
      // (the checker placeholder emits an inline <pattern> whose
      // internal rects have x=0/y=0 in the pattern's own coord
      // space).
      const sized = g.querySelector(
        ":scope > rect, :scope > foreignObject, :scope > image"
      );
      if (!sized) return null;
      return {
        x: parseFloat(sized.getAttribute("x")) || 0,
        y: parseFloat(sized.getAttribute("y")) || 0,
        width: parseFloat(sized.getAttribute("width")) || 0,
        height: parseFloat(sized.getAttribute("height")) || 0,
      };
    },

    // Translates the element group + its selection chrome together,
    // so the dashed outline + drag overlay + resize handles track
    // the element 1:1 during the drag.
    forEachElementGroup(id, fn) {
      const selector =
        `[data-pk-og-element="${id}"], [data-pk-og-selection="${id}"]`;
      this.el.querySelectorAll(selector).forEach(fn);
    },

    applyTempTransform(id, dx, dy) {
      this.forEachElementGroup(id, (g) =>
        g.setAttribute("transform", `translate(${dx} ${dy})`)
      );
    },

    clearTempTransform(id) {
      this.forEachElementGroup(id, (g) =>
        g.removeAttribute("transform")
      );
    },

    // Bakes a `(dx, dy)` drag delta into the element's child
    // coordinates AND its selection-chrome coordinates, then
    // drops the transient `transform`. This produces a DOM that
    // matches what the server will render on the `move_element`
    // ack, so morphdom finds no diff and nothing visibly flickers.
    commitDragBounds(id, dx, dy) {
      const el = this.findElement(id);
      const bounds = el ? this.boundsForElement(id) : null;
      if (!bounds) {
        this.clearTempTransform(id);
        return;
      }

      const newX = bounds.x + dx;
      const newY = bounds.y + dy;

      // Element children (rect, foreignObject, image): update x/y
      // only — width/height are preserved. Direct children so we
      // don't rewrite pattern-internal rects.
      if (el) {
        el.querySelectorAll(
          ":scope > rect, :scope > foreignObject, :scope > image"
        ).forEach((node) => {
          node.setAttribute("x", newX);
          node.setAttribute("y", newY);
        });
        // Pattern (checker placeholder) — keep origin aligned to
        // the moving rect so tiles don't slide during drag.
        el.querySelectorAll(":scope > pattern").forEach((p) => {
          p.setAttribute("x", newX);
          p.setAttribute("y", newY);
        });
        // Center any label text (placeholder "Image" label).
        el.querySelectorAll(":scope > text").forEach((t) => {
          t.setAttribute("x", newX + bounds.width / 2);
          t.setAttribute("y", newY + bounds.height / 2);
        });
      }

      // Selection chrome: outline, drag overlay, resize handles.
      const chrome = this.el.querySelector(
        `[data-pk-og-selection="${id}"]`
      );
      if (chrome) {
        const outline = chrome.querySelector(
          "g[pointer-events='none'] > rect"
        );
        if (outline) {
          outline.setAttribute("x", newX);
          outline.setAttribute("y", newY);
        }

        const overlay = chrome.querySelector("[data-pk-og-drag-handle]");
        if (overlay) {
          overlay.setAttribute("x", newX);
          overlay.setAttribute("y", newY);
        }

        chrome
          .querySelectorAll("[data-pk-og-resize-handle]")
          .forEach((h) => {
            const [cx, cy] = handleAnchor(
              h.dataset.position,
              newX,
              newY,
              bounds.width,
              bounds.height
            );
            h.setAttribute("x", cx - 6);
            h.setAttribute("y", cy - 6);
          });
      }

      // Finally drop the transient `transform` — the element and
      // its chrome are now at their final positions via their
      // coord attributes.
      this.clearTempTransform(id);
    },

    computeResizeBounds(resize) {
      // Prefer the last-applied bounds captured during
      // `applyTempResize`. Fall back to reading the DOM directly
      // (in case something skipped the temp-apply), and finally
      // to the pointerdown origin. Whichever we return goes to
      // the server as the authoritative post-resize bounds.
      if (resize.last) return resize.last;
      const current = this.boundsForElement(resize.id);
      return current || resize.origin;
    },

    applyTempResize(resize, dx, dy) {
      const o = resize.origin;
      let { x, y, width, height } = o;

      switch (resize.position) {
        case "e": width = o.width + dx; break;
        case "w": x = o.x + dx; width = o.width - dx; break;
        case "n": y = o.y + dy; height = o.height - dy; break;
        case "s": height = o.height + dy; break;
        case "ne": y = o.y + dy; width = o.width + dx; height = o.height - dy; break;
        case "nw": x = o.x + dx; y = o.y + dy; width = o.width - dx; height = o.height - dy; break;
        case "se": width = o.width + dx; height = o.height + dy; break;
        case "sw": x = o.x + dx; width = o.width - dx; height = o.height + dy; break;
      }

      width = Math.max(8, width);
      height = Math.max(8, height);

      // Resize the element itself (its sized SVG children).
      // Direct children only — descendants inside <pattern>
      // shouldn't be touched, and the pattern origin is updated
      // separately below.
      const g = this.findElement(resize.id);
      if (g) {
        g.querySelectorAll(
          ":scope > rect, :scope > foreignObject, :scope > image"
        ).forEach((node) => {
          node.setAttribute("x", x);
          node.setAttribute("y", y);
          node.setAttribute("width", width);
          node.setAttribute("height", height);
        });
        // Keep any inline `<pattern>` (image placeholder's
        // checker) anchored to the rect's new top-left so tiles
        // stay aligned during resize.
        g.querySelectorAll(":scope > pattern").forEach((p) => {
          p.setAttribute("x", x);
          p.setAttribute("y", y);
        });
        // Center any label text on the new bounds.
        g.querySelectorAll(":scope > text").forEach((t) => {
          t.setAttribute("x", x + width / 2);
          t.setAttribute("y", y + height / 2);
        });
      }

      // Also update the selection chrome (outline rect, drag
      // overlay, 8 corner/edge handles) so they track the element
      // during the drag rather than orphaning at the original
      // bounds. Each piece uses its own selector — a broad
      // `:scope > rect` would also match the 12×12 handles and
      // resize them to the element bounds, which is what caused
      // the "everything turns into blue boxes" bug.
      const chrome = this.el.querySelector(
        `[data-pk-og-selection="${resize.id}"]`
      );
      if (chrome) {
        // Dashed outline (rect inside the non-interactive <g>).
        const outline = chrome.querySelector("g[pointer-events='none'] > rect");
        if (outline) {
          outline.setAttribute("x", x);
          outline.setAttribute("y", y);
          outline.setAttribute("width", width);
          outline.setAttribute("height", height);
        }

        // Drag overlay (transparent rect covering the element).
        const overlay = chrome.querySelector("[data-pk-og-drag-handle]");
        if (overlay) {
          overlay.setAttribute("x", x);
          overlay.setAttribute("y", y);
          overlay.setAttribute("width", width);
          overlay.setAttribute("height", height);
        }

        // 8 resize handles — reposition only. Their 12×12 size
        // MUST NOT change or they blot out the canvas.
        chrome
          .querySelectorAll("[data-pk-og-resize-handle]")
          .forEach((h) => {
            const [cx, cy] = handleAnchor(h.dataset.position, x, y, width, height);
            h.setAttribute("x", cx - 6);
            h.setAttribute("y", cy - 6);
          });
      }

      resize.last = { x, y, width, height };
    },

    clearTempResize(id) {
      // No-op: the server will re-render with the final bounds.
      // (We don't restore the old bounds because the temp resize
      // wrote them in place; the LV diff will reconcile.)
    },
  };

  // Wrapper hook for keyboard + focus management on the editor root.
  Hooks.PhoenixKitOGEditor = {
    mounted() {
      const onKeyDown = (evt) => {
        // Don't hijack inputs.
        const t = evt.target;
        if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) {
          return;
        }

        if (evt.key === "Delete" || evt.key === "Backspace") {
          evt.preventDefault();
          this.pushEvent("delete_selected", {});
        } else if (evt.key === "Escape") {
          this.pushEvent("deselect", {});
        } else if (evt.key.startsWith("Arrow")) {
          evt.preventDefault();
          this.pushEvent("nudge", { key: evt.key, shift: evt.shiftKey });
        } else if ((evt.ctrlKey || evt.metaKey) && evt.key === "s") {
          evt.preventDefault();
          this.pushEvent("save_now", {});
        }
      };

      window.addEventListener("keydown", onKeyDown);
      this._cleanup = () => window.removeEventListener("keydown", onKeyDown);
    },

    destroyed() {
      this._cleanup && this._cleanup();
    },
  };
})();
