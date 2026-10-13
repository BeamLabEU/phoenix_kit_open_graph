// PhoenixKitOG editor hook — keyboard shortcuts at the page level
// (PhoenixKitOGEditor). Pointer gestures on the stage belong to
// open_fresco's own OpenFrescoEditor hook. Shipped via
// `PhoenixKitOG.js_sources/0` so core's :phoenix_kit_js_sources compiler
// folds it into the host's single LiveSocket at construction — the ONLY
// registration that survives LiveView navigation (an inline <script> only
// runs on a hard load, not a morphdom patch, so the hook would be silently
// absent when navigating into the editor from the list).
// Registered on window.PhoenixKitOGHooks, which the host spreads into hooks.

(() => {
  // What a keydown means to the editor: null (not ours — leave it to the
  // browser), or {action, prevent} with action "save" | "delete" | "deselect"
  // | "nudge". A pure function of the event and three facts about the page so
  // the rules can be tested without a DOM.
  //
  //   formControl — the target is an input, textarea, select or
  //                 contenteditable. Backspace in a focused <select> is a habit
  //                 from text fields, not a request to delete the selection.
  //   inStage     — the OpenFresco stage owns focus; ITS keyboard handling
  //                 applies (Tab-cycle, arrow-nudge, Delete, multi-select
  //                 aware), and answering too would double every action.
  //   overlayOpen — a dialog, modal or popover is open over the editor: keys
  //                 belong to it, not to the canvas behind it.
  function editorKeyAction(evt, ctx) {
    // Ctrl/Cmd+S saves from anywhere on the page, so it is decided first.
    if ((evt.ctrlKey || evt.metaKey) && !evt.altKey && (evt.key === "s" || evt.key === "S")) {
      return { action: "save", prevent: true };
    }

    if (ctx.overlayOpen || ctx.formControl || ctx.inStage) return null;

    // Every other shortcut is a bare key. With a modifier held the combination
    // is the browser's (Alt+ArrowLeft is Back, Cmd+Backspace deletes a line).
    if (evt.altKey || evt.ctrlKey || evt.metaKey) return null;

    if (evt.key === "Delete" || evt.key === "Backspace") {
      return { action: "delete", prevent: true };
    }
    if (evt.key === "Escape") return { action: "deselect", prevent: false };
    if (typeof evt.key === "string" && evt.key.startsWith("Arrow")) {
      return { action: "nudge", prevent: true };
    }
    return null;
  }

  if (typeof module === "object" && module.exports) {
    module.exports.editorKeyAction = editorKeyAction;
  }

  // Register once even if the bundle is somehow evaluated twice. No window
  // means the bundle was loaded for its exports (the node tests).
  if (typeof window === "undefined") return;
  if (window.__pkOgEditorRegistered) return;
  window.__pkOgEditorRegistered = true;

  const Hooks = (window.PhoenixKitOGHooks = window.PhoenixKitOGHooks || {});

  function isFormControl(t) {
    return !!(
      t &&
      (t.tagName === "INPUT" ||
        t.tagName === "TEXTAREA" ||
        t.tagName === "SELECT" ||
        t.isContentEditable)
    );
  }

  function overlayOpen() {
    if (document.querySelector("dialog[open], .modal-open")) return true;
    try {
      return !!document.querySelector(":popover-open");
    } catch (_) {
      // A browser without the Popover API has no open popover.
      return false;
    }
  }

  // Wrapper hook for keyboard handling on the editor root.
  Hooks.PhoenixKitOGEditor = {
    mounted() {
      const onKeyDown = (evt) => {
        const t = evt.target;
        const decision = editorKeyAction(evt, {
          formControl: isFormControl(t),
          inStage: !!(t && t.closest && t.closest('[phx-hook="OpenFrescoEditor"]')),
          overlayOpen: overlayOpen(),
        });
        if (!decision) return;
        if (decision.prevent) evt.preventDefault();

        if (decision.action === "save") {
          this.pushEvent("save_now", {});
        } else if (decision.action === "delete") {
          this.pushEvent("delete_selected", {});
        } else if (decision.action === "deselect") {
          this.pushEvent("deselect", {});
        } else if (decision.action === "nudge") {
          this.pushEvent("nudge", { key: evt.key, shift: evt.shiftKey });
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
