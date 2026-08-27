import assert from "node:assert/strict";
import test from "node:test";

import {
  explorerFiltersFromFormData,
  explorerFiltersFromSearch,
  explorerPersistableFilters,
  explorerSearchFromFilters,
  hasExplorerFilterSearch,
} from "../../../app/javascript/utils/transaction_explorer_history.mjs";

test("round trips explicit selections and optional empty filters", () => {
  const filters = {
    entity_ids: ["jpw"],
    years: ["2026"],
    months: [],
    types: ["Expense", "Income"],
    detail_category_ids: [],
    wdg_rollup_ids: [],
    include_tag_ids: ["setup"],
    exclude_tag_ids: [],
    search: "rent",
  };

  const search = explorerSearchFromFilters(filters);

  assert.equal(hasExplorerFilterSearch(search), true);
  assert.deepEqual(explorerFiltersFromSearch(search), filters);
});

test("reads the Explorer form contract and removes the empty sentinel", () => {
  const formData = new FormData();
  formData.append("entity_ids[]", "__none__");
  formData.append("entity_ids[]", "jpw");
  formData.append("years[]", "__none__");
  formData.append("months[]", "__none__");
  formData.append("months[]", "8");
  formData.append("types[]", "__none__");
  formData.append("types[]", "Expense");
  formData.append("search", "  grocery  ");

  assert.deepEqual(explorerFiltersFromFormData(formData), {
    entity_ids: ["jpw"],
    years: [],
    months: ["8"],
    types: ["Expense"],
    search: "grocery",
  });
});

test("does not mistake unrelated query parameters for Explorer state", () => {
  assert.equal(hasExplorerFilterSearch("?page=2"), false);
  assert.deepEqual(explorerFiltersFromSearch("?page=2"), {});
});

test("excludes free-text search from persistent filter storage", () => {
  const persistent = explorerPersistableFilters({
    entity_ids: ["jpw"],
    search: "private merchant text",
  });

  assert.deepEqual(persistent, { entity_ids: ["jpw"] });
  assert.doesNotMatch(explorerSearchFromFilters(persistent), /search|merchant/);
});
