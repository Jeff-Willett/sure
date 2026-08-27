import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const controllerUrl = new URL(
  "../../../app/javascript/controllers/transaction_explorer_slicer_controller.js",
  import.meta.url,
);

test("bulk slicer changes notify the workspace before form submission", async () => {
  const source = await readFile(controllerUrl, "utf8");
  const notification = source.indexOf('new CustomEvent("explorer-slicer-change"');
  const submission = source.indexOf("requestSubmit()");

  assert.notEqual(notification, -1);
  assert.notEqual(submission, -1);
  assert.ok(notification < submission);
});
