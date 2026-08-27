import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const controllerUrl = new URL(
  "../../../app/javascript/controllers/transaction_explorer_tabulator_controller.js",
  import.meta.url,
);

test("Tabulator controller imports view state through the import map", async () => {
  const source = await readFile(controllerUrl, "utf8");

  assert.match(source, /from ["']utils\/transaction_explorer_view_state["']/);
  assert.doesNotMatch(
    source,
    /from ["']\.\.\/utils\/transaction_explorer_view_state\.mjs["']/,
  );
});
