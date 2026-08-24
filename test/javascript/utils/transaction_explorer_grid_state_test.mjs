import assert from "node:assert/strict"
import test from "node:test"

import {
  focusFallback,
  nextEditableCell,
  shouldOpenEditor,
} from "../../../app/javascript/utils/transaction_explorer_grid_state.mjs"

const cells = [
  { entryId: "a", scheme: "WDG" },
  { entryId: "a", scheme: "JPW" },
  { entryId: "b", scheme: "WDG" },
  { entryId: "b", scheme: "JPW" },
  { entryId: "c", scheme: "WDG" },
  { entryId: "c", scheme: "JPW" },
]

test("moves forward and backward by arrow and tab keys", () => {
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[1],
      key: "ArrowDown",
    }),
    cells[3],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[3],
      key: "ArrowUp",
    }),
    cells[1],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[1],
      key: "Tab",
    }),
    cells[2],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[2],
      key: "Tab",
      shiftKey: true,
    }),
    cells[1],
  )
})

test("clamps movement at first and last positions", () => {
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[0],
      key: "ArrowUp",
    }),
    cells[0],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[5],
      key: "ArrowDown",
    }),
    cells[5],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[5],
      key: "Tab",
    }),
    cells[5],
  )
  assert.equal(
    nextEditableCell({
      cells,
      active: cells[0],
      key: "Tab",
      shiftKey: true,
    }),
    cells[0],
  )
})

test("returns null when active cell cannot be found", () => {
  assert.equal(
    nextEditableCell({
      cells,
      active: { entryId: "z", scheme: "WDG" },
      key: "ArrowRight",
    }),
    null,
  )
})

test("opens editor for explicit keys and printable characters", () => {
  assert.equal(shouldOpenEditor({ key: "Enter" }), true)
  assert.equal(shouldOpenEditor({ key: "F2" }), true)
  assert.equal(shouldOpenEditor({ key: "a", printable: true }), true)
})

test("does not open editor for non-printable or unrelated keys", () => {
  assert.equal(shouldOpenEditor({ key: "ArrowDown", printable: true }), false)
  assert.equal(shouldOpenEditor({ key: "a" }), false)
  assert.equal(shouldOpenEditor({ key: "Tab", printable: true }), false)
})

test("focuses the closest available cell when previous is deleted", () => {
  const remaining = [
    { entryId: "a", scheme: "WDG" },
    { entryId: "a", scheme: "JPW" },
    { entryId: "c", scheme: "WDG" },
    { entryId: "c", scheme: "JPW" },
    { entryId: "d", scheme: "WDG" },
    { entryId: "d", scheme: "JPW" },
  ]

  assert.deepEqual(
    focusFallback({
      cells: remaining,
      previous: { entryId: "b", scheme: "JPW", index: 3 },
    }),
    { entryId: "c", scheme: "JPW" },
  )
})

test("falls back to first same-scheme cell if no stable index is available", () => {
  const remaining = [
    { entryId: "a", scheme: "JPW" },
    { entryId: "b", scheme: "WDG" },
  ]

  assert.deepEqual(
    focusFallback({
      cells: remaining,
      previous: { entryId: "c", scheme: "JPW" },
    }),
    { entryId: "a", scheme: "JPW" },
  )
})
