export const TRANSACTION_EXPLORER_VIEW_STATE_KEY =
  "myfin:transaction-explorer:view-state:v1"

const DEFAULT_STATE = Object.freeze({
  layout: "fitDataStretch",
  rollupsOpen: false,
  columns: null,
})

const VALID_LAYOUTS = new Set(["fitDataStretch", "fitColumns"])

export function parseExplorerViewState(serialized) {
  if (!serialized) return { ...DEFAULT_STATE }

  try {
    const value = JSON.parse(serialized)
    if (!isValidState(value)) return { ...DEFAULT_STATE }

    return value
  } catch (_error) {
    return { ...DEFAULT_STATE }
  }
}

export function serializeExplorerViewState(state) {
  if (!isValidState(state)) return JSON.stringify(DEFAULT_STATE)

  return JSON.stringify(state)
}

function isValidState(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    VALID_LAYOUTS.has(value.layout) &&
    typeof value.rollupsOpen === "boolean" &&
    isValidColumns(value.columns)
  )
}

function isValidColumns(columns) {
  if (columns === null) return true
  if (!Array.isArray(columns) || columns.length === 0) return false

  return columns.every(
    (column) =>
      column !== null &&
      typeof column === "object" &&
      typeof column.field === "string" &&
      column.field.length > 0 &&
      Number.isFinite(column.width) &&
      column.width > 0 &&
      typeof column.visible === "boolean",
  )
}
