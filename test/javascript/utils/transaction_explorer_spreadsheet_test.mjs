import assert from "node:assert/strict";
import test from "node:test";

import {
  fillDownEdits,
  parseClipboardText,
  pasteEdits,
  selectionRange,
} from "../../../app/javascript/utils/transaction_explorer_spreadsheet.mjs";

const cells = [
  { entryId: "a", scheme: "WDG", categoryId: "w1", label: "Home" },
  { entryId: "a", scheme: "JPW", categoryId: "j1", label: "Rent" },
  { entryId: "b", scheme: "WDG", categoryId: "w2", label: "Shopping" },
  { entryId: "b", scheme: "JPW", categoryId: "j2", label: "Groceries" },
  { entryId: "c", scheme: "WDG", categoryId: "w3", label: "Health" },
  { entryId: "c", scheme: "JPW", categoryId: "j3", label: "Veterinary" },
];

const categories = {
  WDG: new Map([["Home", "w1"], ["Shopping", "w2"], ["Health", "w3"]]),
  JPW: new Map([["Rent", "j1"], ["Groceries", "j2"], ["Veterinary", "j3"]]),
};

test("selects a rectangular category-cell range", () => {
  assert.deepEqual(
    selectionRange(cells, cells[0], cells[3]),
    cells.slice(0, 4),
  );
  assert.deepEqual(
    selectionRange(cells, cells[1], cells[5]),
    [cells[1], cells[3], cells[5]],
  );
});

test("parses tab and newline clipboard text", () => {
  assert.deepEqual(parseClipboardText("Home\tRent\nShopping\tGroceries"), [
    ["Home", "Rent"],
    ["Shopping", "Groceries"],
  ]);
});

test("resolves exact existing category names and rejects unknown names", () => {
  assert.deepEqual(
    pasteEdits({ cells, target: cells[2], matrix: [["Home", "Rent"]], categories }),
    [
      { entryId: "b", scheme: "WDG", categoryId: "w1", expectedCategoryId: "w2" },
      { entryId: "b", scheme: "JPW", categoryId: "j1", expectedCategoryId: "j2" },
    ],
  );

  assert.throws(
    () => pasteEdits({ cells, target: cells[2], matrix: [["New category"]], categories }),
    /Unknown WDG category/,
  );
});

test("fills selected rows from the top row without changing the source", () => {
  assert.deepEqual(fillDownEdits({ cells, selection: cells }), [
    { entryId: "b", scheme: "WDG", categoryId: "w1", expectedCategoryId: "w2" },
    { entryId: "b", scheme: "JPW", categoryId: "j1", expectedCategoryId: "j2" },
    { entryId: "c", scheme: "WDG", categoryId: "w1", expectedCategoryId: "w3" },
    { entryId: "c", scheme: "JPW", categoryId: "j1", expectedCategoryId: "j3" },
  ]);
});
