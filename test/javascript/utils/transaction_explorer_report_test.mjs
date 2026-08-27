import assert from "node:assert/strict";
import test from "node:test";

import { deriveExplorerReport } from "../../../app/javascript/utils/transaction_explorer_report.mjs";

const dataset = [
  row({
    id: "purchase",
    date: "2026-08-10",
    entity_amounts: { jpw: -100, gci: -50 },
    detail_category_id: "groceries",
    detail_category: "Groceries",
    wdg_rollup_id: "home",
    wdg_rollup: "Home Living",
    tag_ids: ["setup"],
    tags: "Apartment Setup",
  }),
  row({
    id: "refund",
    date: "2026-08-12",
    entity_amounts: { jpw: 20 },
    detail_category_id: "groceries",
    detail_category: "Groceries",
    wdg_rollup_id: "home",
    wdg_rollup: "Home Living",
  }),
  row({
    id: "income",
    date: "2026-08-15",
    entity_amounts: { jpw: 1_000 },
    detail_category_id: "payroll",
    detail_category: "Payroll",
    wdg_rollup_id: "income-rollup",
    wdg_rollup: "Income",
  }),
  row({
    id: "transfer",
    date: "2026-08-18",
    entity_amounts: { jpw: -200 },
    detail_category_id: "card-payment",
    detail_category: "Card payment",
    wdg_rollup_id: "transfer-rollup",
    wdg_rollup: "Transfer",
    transfer: true,
  }),
  row({
    id: "gci-expense",
    date: "2026-07-09",
    entity_amounts: { gci: -75 },
    detail_scheme: "GCI",
    detail_category_id: "software",
    detail_category: "Software",
    wdg_rollup_id: null,
    wdg_rollup: null,
    description: "Hosting service",
  }),
];

test("derives expense totals and rollups from the same filtered rows", () => {
  const report = deriveExplorerReport(dataset, {
    entity_ids: ["jpw"],
    years: ["2026"],
    months: ["8"],
    types: ["Expense"],
  });

  assert.deepEqual(
    report.rows.map(({ id, amount, type }) => ({ id, amount, type })),
    [
      { id: "refund", amount: 20, type: "Refund" },
      { id: "purchase", amount: -100, type: "Expense" },
    ],
  );
  assert.deepEqual(report.metrics, {
    transactions: 2,
    expenses: 80,
    income: 0,
    transfer_net: 0,
  });
  assert.equal(report.rollup.length, 1);
  assert.equal(report.rollup[0].type, "Expense");
  assert.equal(report.rollup[0].amount, -80);
  assert.equal(report.rollup[0].groups[0].amount, -80);
  assert.equal(report.rollup[0].groups[0].categories[0].count, 2);
  assert.equal(
    report.rows.reduce((sum, candidate) => sum + candidate.amount, 0),
    report.rollup.reduce((sum, candidate) => sum + candidate.amount, 0),
  );
});

test("recalculates allocation amounts and types for the selected entities", () => {
  const jpw = deriveExplorerReport(dataset, {
    entity_ids: ["jpw"],
    types: ["Expense", "Income", "Transfer"],
  });
  const gci = deriveExplorerReport(dataset, {
    entity_ids: ["gci"],
    types: ["Expense", "Income", "Transfer"],
  });

  assert.equal(jpw.rows.find(({ id }) => id === "purchase").amount, -100);
  assert.equal(gci.rows.find(({ id }) => id === "purchase").amount, -50);
  assert.equal(jpw.rows.find(({ id }) => id === "purchase").entity, "JPW");
  assert.equal(gci.rows.find(({ id }) => id === "purchase").entity, "CGI");
  assert.equal(jpw.rows.find(({ id }) => id === "income").type, "Income");
  assert.equal(jpw.rows.find(({ id }) => id === "transfer").type, "Transfer");
  assert.equal(gci.rows.some(({ id }) => id === "income"), false);
});

test("applies search, durable category IDs, and tag inclusion and exclusion", () => {
  const report = deriveExplorerReport(dataset, {
    search: "hosting",
    detail_category_ids: ["software"],
    include_tag_ids: [],
    exclude_tag_ids: ["setup"],
  });

  assert.deepEqual(report.rows.map(({ id }) => id), ["gci-expense"]);

  const setup = deriveExplorerReport(dataset, {
    include_tag_ids: ["setup"],
    exclude_tag_ids: [],
  });
  assert.deepEqual(setup.rows.map(({ id }) => id), ["purchase"]);
});

test("preserves explicit empty and optional empty filter semantics", () => {
  assert.deepEqual(deriveExplorerReport(dataset, { entity_ids: [] }).rows, []);
  assert.deepEqual(deriveExplorerReport(dataset, { years: [] }).rows, []);
  assert.equal(
    deriveExplorerReport(dataset, { wdg_rollup_ids: [], include_tag_ids: [] }).rows.length,
    dataset.length,
  );
});

test("keeps uncategorized rows when the category filter is implicit", () => {
  const uncategorized = row({
    id: "uncategorized",
    detail_category_id: null,
    detail_category: "Uncategorized",
  });

  assert.deepEqual(
    deriveExplorerReport([uncategorized], {}).rows.map(({ id }) => id),
    ["uncategorized"],
  );
});

test("filters explicitly to uncategorized rows", () => {
  const uncategorized = row({
    id: "uncategorized",
    detail_category_id: null,
    detail_category: "Uncategorized",
  });
  const categorized = row({
    id: "categorized",
    detail_category_id: "groceries",
    detail_category: "Groceries",
  });

  assert.deepEqual(
    deriveExplorerReport([uncategorized, categorized], {
      detail_category_ids: ["__uncategorized__"],
    }).rows.map(({ id }) => id),
    ["uncategorized"],
  );
});

test("builds entity rollups when the reporting profile is not WDG", () => {
  const report = deriveExplorerReport(
    dataset,
    { entity_ids: ["gci"] },
    { rollupMode: "entity" },
  );

  const expense = report.rollup.find(({ type }) => type === "Expense");
  assert.deepEqual(
    expense.groups.map(({ entity_id, wdg }) => ({ entity_id, wdg })),
    [{ entity_id: null, wdg: "Needs entity" }],
  );
});

test("sums fractional allocation decimals without binary drift", () => {
  const report = deriveExplorerReport([
    row({ id: "fraction-a", entity_amounts: { jpw: "-0.1" } }),
    row({ id: "fraction-b", entity_amounts: { jpw: "-0.2" } }),
  ]);

  assert.equal(report.metrics.expenses, 0.3);
  assert.equal(report.rollup[0].amount, -0.3);
  assert.equal(
    report.rows.reduce((total, candidate) => total + candidate.amount, 0),
    -0.30000000000000004,
  );
});

test("does not contain persistent storage or network access", async () => {
  const source = await import("node:fs/promises").then(({ readFile }) =>
    readFile(
      new URL("../../../app/javascript/utils/transaction_explorer_report.mjs", import.meta.url),
      "utf8",
    ),
  );

  assert.doesNotMatch(source, /localStorage|sessionStorage|indexedDB|fetch\s*\(/);
});

function row(overrides) {
  return {
    id: "row",
    date: "2026-08-01",
    entity_ids: Object.keys(overrides.entity_amounts || { jpw: -1 }),
    entity_amounts: { jpw: -1 },
    entity_labels: { jpw: "JPW", gci: "CGI" },
    entity_id: null,
    entity_name: null,
    entity: "JPW",
    transfer: false,
    wdg: "Shopping",
    wdg_category_id: "shopping",
    wdg_rollup: "Shopping",
    wdg_rollup_id: "shopping",
    jpw: "Uncategorized",
    detail_category: "Uncategorized",
    detail_category_id: null,
    detail_scheme: "JPW",
    tag_ids: [],
    tags: "",
    description: "Sample transaction",
    account: "Checking",
    ...overrides,
  };
}
