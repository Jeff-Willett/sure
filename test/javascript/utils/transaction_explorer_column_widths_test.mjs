import assert from "node:assert/strict"
import test from "node:test"

import {
  TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY,
  TRANSACTION_EXPLORER_COLUMNS,
  clampWidth,
  deriveDesktopStickyOffsets,
  parseStoredWidths,
  resizeWidths,
  resetWidth,
} from "../../../app/javascript/utils/transaction_explorer_column_widths.mjs"

test("exports a stable column-width storage key", () => {
  assert.equal(TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY, "transaction-explorer:column-widths:v1")
})

test("clamps width by min width and rounds down to integer", () => {
  assert.equal(clampWidth("date", 60), TRANSACTION_EXPLORER_COLUMNS.date.minWidth)
  assert.equal(
    clampWidth("date", 140.9),
    TRANSACTION_EXPLORER_COLUMNS.date.defaultWidth + 0,
  )
})

test("throws for unknown columns when clamping", () => {
  assert.throws(
    () => clampWidth("merchant", 100),
    /Unknown transaction explorer column/,
  )
})

test("resizes one column without mutating other columns", () => {
  const current = {
    date: 140,
    entity: 260,
    description: 360,
  }

  const next = resizeWidths(current, "date", 20)
  assert.equal(next.date, 160)
  assert.equal(next.entity, 260)
  assert.equal(next.description, 360)
  assert.notEqual(next, current)
  assert.equal(current.date, 140)
})

test("resets one column back to default", () => {
  assert.equal(resetWidth("entity"), TRANSACTION_EXPLORER_COLUMNS.entity.defaultWidth)
})

test("rejects malformed stored payload", () => {
  assert.throws(
    () => parseStoredWidths("not-json"),
    /Malformed transaction explorer column width data/,
  )
})

test("rejects unknown columns from storage", () => {
  assert.throws(
    () =>
      parseStoredWidths(
        JSON.stringify({
          date: 130,
          merchant: 200,
        }),
      ),
    /Unknown transaction explorer column/,
  )
})

test("keeps missing columns and normalizes parsed widths", () => {
  const widths = parseStoredWidths(JSON.stringify({ description: 9001 }))
  assert.equal(widths.date, TRANSACTION_EXPLORER_COLUMNS.date.defaultWidth)
  assert.equal(widths.entity, TRANSACTION_EXPLORER_COLUMNS.entity.defaultWidth)
  assert.equal(widths.description, 9001)
})

test("derives sticky column offsets from Date and Entity widths", () => {
  const offsets = deriveDesktopStickyOffsets({ date: 200, entity: 300 })
  assert.equal(offsets.date, 0)
  assert.equal(offsets.entity, 200)
})
