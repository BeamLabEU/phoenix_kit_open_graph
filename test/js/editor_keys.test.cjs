"use strict";

// Unit tests for `editorKeyAction` in priv/static/assets/phoenix_kit_og.js —
// the decision behind the editor's page-level keyboard shortcuts.
//
// Run: mix test.js  (node --test needs the explicit file on Node 25)

const test = require("node:test");
const assert = require("node:assert/strict");

const { editorKeyAction } = require("../../priv/static/assets/phoenix_kit_og.js");

const page = { formControl: false, inStage: false, overlayOpen: false };
const key = (k, mods = {}) => ({
  key: k,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  shiftKey: false,
  ...mods,
});

const contexts = {
  page,
  "form control": { ...page, formControl: true },
  stage: { ...page, inStage: true },
  "open overlay": { ...page, overlayOpen: true },
};

test("Ctrl+S and Cmd+S save from every context, and stop the browser's own save", () => {
  for (const [name, ctx] of Object.entries(contexts)) {
    for (const mods of [{ ctrlKey: true }, { metaKey: true }]) {
      assert.deepEqual(
        editorKeyAction(key("s", mods), ctx),
        { action: "save", prevent: true },
        `${name} ${JSON.stringify(mods)}`
      );
    }
  }
});

test("a bare s is not a save", () => {
  assert.equal(editorKeyAction(key("s"), page), null);
});

test("bare editor keys act on the canvas when nothing else owns the keyboard", () => {
  assert.deepEqual(editorKeyAction(key("Delete"), page), { action: "delete", prevent: true });
  assert.deepEqual(editorKeyAction(key("Backspace"), page), { action: "delete", prevent: true });
  assert.deepEqual(editorKeyAction(key("Escape"), page), { action: "deselect", prevent: false });
  assert.deepEqual(editorKeyAction(key("ArrowLeft"), page), { action: "nudge", prevent: true });
  assert.deepEqual(editorKeyAction(key("ArrowDown", { shiftKey: true }), page), {
    action: "nudge",
    prevent: true,
  });
});

test("a form control, the stage and an open overlay each keep every editor key", () => {
  for (const name of ["form control", "stage", "open overlay"]) {
    for (const k of ["Delete", "Backspace", "Escape", "ArrowLeft", "ArrowUp"]) {
      assert.equal(editorKeyAction(key(k), contexts[name]), null, `${name} ${k}`);
    }
  }
});

test("a held Alt, Ctrl or Meta leaves the combination to the browser", () => {
  for (const mods of [{ altKey: true }, { ctrlKey: true }, { metaKey: true }]) {
    for (const k of ["ArrowLeft", "ArrowRight", "Backspace", "Delete", "Escape"]) {
      assert.equal(editorKeyAction(key(k, mods), page), null, `${JSON.stringify(mods)} ${k}`);
    }
  }
});

test("unrelated keys are ignored", () => {
  assert.equal(editorKeyAction(key("a"), page), null);
  assert.equal(editorKeyAction(key("Enter"), page), null);
  assert.equal(editorKeyAction(key("Tab"), page), null);
});
