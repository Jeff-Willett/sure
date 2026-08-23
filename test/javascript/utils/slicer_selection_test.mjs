import assert from "node:assert/strict";
import test from "node:test";

import {
  checkedStateForMode,
  uniformCheckedState,
} from "../../../app/javascript/utils/slicer_selection.mjs";

test("single selection keeps only the newly checked item", () => {
  assert.deepEqual(
    checkedStateForMode({ current: [ true, true, false ], changedIndex: 2, checked: true, multiple: false }),
    [ false, false, true ],
  );
});

test("multiple selection preserves the other checked items", () => {
  assert.deepEqual(
    checkedStateForMode({ current: [ true, true, false ], changedIndex: 2, checked: true, multiple: true }),
    [ true, true, true ],
  );
});

test("select all and clear all produce uniform checkbox states", () => {
  assert.deepEqual(uniformCheckedState(3, true), [ true, true, true ]);
  assert.deepEqual(uniformCheckedState(3, false), [ false, false, false ]);
});
