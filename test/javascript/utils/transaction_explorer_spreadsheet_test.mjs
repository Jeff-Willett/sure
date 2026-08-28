import assert from "node:assert/strict";
import test from "node:test";

import * as spreadsheet from "../../../app/javascript/utils/transaction_explorer_spreadsheet.mjs";
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

const tabulatorCells = [
  detailCell("a", "Donna", "category-donna"),
  tagsCell("a", [ "tag-family", "tag-zelle" ], [ "Family", "Zelle" ]),
  detailCell("b", "Rent", "category-rent"),
  tagsCell("b", [ "tag-home" ], [ "Home" ]),
  detailCell("c", "Shopping", "category-shopping"),
  tagsCell("c", [ "tag-card" ], [ "Card" ]),
];

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

test("selects a rectangular Detail category and Tags range", () => {
  assert.equal(typeof spreadsheet.tabulatorSelectionRange, "function");
  assert.deepEqual(
    spreadsheet.tabulatorSelectionRange(
      tabulatorCells,
      tabulatorCells[0],
      tabulatorCells[3],
    ),
    tabulatorCells.slice(0, 4),
  );
});

test("locks pointer selection to the anchor column", () => {
  assert.deepEqual(
    spreadsheet.tabulatorSelectionRange(
      tabulatorCells,
      tabulatorCells[0],
      tabulatorCells[3],
      { lockField: true },
    ),
    [ tabulatorCells[0], tabulatorCells[2] ],
  );
});

test("copies a rectangular Detail category and Tags range as typed clipboard data", () => {
  assert.equal(typeof spreadsheet.tabulatorCopyPayload, "function");
  assert.deepEqual(
    spreadsheet.tabulatorCopyPayload(tabulatorCells.slice(0, 4)),
    {
      text: "Donna\tFamily, Zelle\nRent\tHome",
      fields: [ "detail_category", "tags" ],
      rows: [
        [
          { categoryId: "category-donna", label: "Donna" },
          { tagIds: [ "tag-family", "tag-zelle" ], label: "Family, Zelle" },
        ],
        [
          { categoryId: "category-rent", label: "Rent" },
          { tagIds: [ "tag-home" ], label: "Home" },
        ],
      ],
    },
  );
});

test("fills selected Detail category cells from one copied category", () => {
  assert.equal(typeof spreadsheet.tabulatorPasteEdits, "function");
  assert.deepEqual(
    spreadsheet.tabulatorPasteEdits({
      cells: tabulatorCells,
      selection: [ tabulatorCells[2], tabulatorCells[4] ],
      active: tabulatorCells[2],
      clipboard: {
        fields: [ "detail_category" ],
        rows: [ [ { categoryId: "category-donna", label: "Donna" } ] ],
      },
    }),
    [
      {
        field: "detail_category",
        entryId: "b",
        schemeId: "scheme-jpw",
        categoryId: "category-donna",
        expectedCategoryId: "category-rent",
      },
      {
        field: "detail_category",
        entryId: "c",
        schemeId: "scheme-jpw",
        categoryId: "category-donna",
        expectedCategoryId: "category-shopping",
      },
    ],
  );
});

test("replaces each selected Tags cell with the complete copied tag list", () => {
  assert.equal(typeof spreadsheet.tabulatorPasteEdits, "function");
  assert.deepEqual(
    spreadsheet.tabulatorPasteEdits({
      cells: tabulatorCells,
      selection: [ tabulatorCells[3], tabulatorCells[5] ],
      active: tabulatorCells[3],
      clipboard: {
        fields: [ "tags" ],
        rows: [ [ { tagIds: [ "tag-family", "tag-zelle" ], label: "Family, Zelle" } ] ],
      },
    }),
    [
      {
        field: "tags",
        entryId: "b",
        tagIds: [ "tag-family", "tag-zelle" ],
        expectedTagIds: [ "tag-home" ],
      },
      {
        field: "tags",
        entryId: "c",
        tagIds: [ "tag-family", "tag-zelle" ],
        expectedTagIds: [ "tag-card" ],
      },
    ],
  );
});

test("pastes a two-column block from one anchor cell", () => {
  assert.equal(typeof spreadsheet.tabulatorPasteEdits, "function");
  assert.deepEqual(
    spreadsheet.tabulatorPasteEdits({
      cells: tabulatorCells,
      selection: [ tabulatorCells[2] ],
      active: tabulatorCells[2],
      clipboard: spreadsheet.tabulatorCopyPayload(tabulatorCells.slice(0, 4)),
    }),
    [
      {
        field: "detail_category",
        entryId: "b",
        schemeId: "scheme-jpw",
        categoryId: "category-donna",
        expectedCategoryId: "category-rent",
      },
      {
        field: "tags",
        entryId: "b",
        tagIds: [ "tag-family", "tag-zelle" ],
        expectedTagIds: [ "tag-home" ],
      },
      {
        field: "detail_category",
        entryId: "c",
        schemeId: "scheme-jpw",
        categoryId: "category-rent",
        expectedCategoryId: "category-shopping",
      },
      {
        field: "tags",
        entryId: "c",
        tagIds: [ "tag-home" ],
        expectedTagIds: [ "tag-card" ],
      },
    ],
  );
});

test("rejects a copied Detail category pasted into Tags", () => {
  assert.equal(typeof spreadsheet.tabulatorPasteEdits, "function");
  assert.throws(
    () => spreadsheet.tabulatorPasteEdits({
      cells: tabulatorCells,
      selection: [ tabulatorCells[3] ],
      active: tabulatorCells[3],
      clipboard: {
        fields: [ "detail_category" ],
        rows: [ [ { categoryId: "category-donna", label: "Donna" } ] ],
      },
    }),
    /cannot be pasted into Tags/i,
  );
});

function detailCell(entryId, label, categoryId) {
  return {
    entryId,
    field: "detail_category",
    schemeId: "scheme-jpw",
    categoryId,
    tagIds: [],
    label,
  };
}

function tagsCell(entryId, tagIds, tagNames) {
  return {
    entryId,
    field: "tags",
    schemeId: "scheme-jpw",
    categoryId: null,
    tagIds,
    label: tagNames.join(", "),
  };
}
