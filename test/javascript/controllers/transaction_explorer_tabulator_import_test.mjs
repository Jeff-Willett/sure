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

test("Tabulator readiness does not depend on visible rows", async () => {
  const source = await readFile(controllerUrl, "utf8");

  assert.match(source, /this\.tableStateRestored = false/);
  assert.doesNotMatch(source, /table\.getRows\(\)\.length === 0/);
});

test("working-set callbacks are scoped to the active connection", async () => {
  const source = await readFile(controllerUrl, "utf8");

  assert.match(source, /Symbol\("transaction-explorer-load"\)/);
  assert.match(source, /this\.loadToken !== loadToken/);
  assert.match(source, /this\.workingDataAbortController\.abort\(\)/);
});

test("empty filters do not send an empty updateData payload", async () => {
  const source = await readFile(controllerUrl, "utf8");

  assert.match(source, /if \(report\.rows\.length > 0\)/);
  assert.match(source, /if \(this\.currentReport\.rows\.length > 0\)/);
});
