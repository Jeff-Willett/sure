const GRID_ADVANCE_BY_KEY = {
  ArrowUp: -2,
  ArrowDown: 2,
  ArrowLeft: -1,
  Tab: 1,
}

const OPEN_EDITOR_KEYS = new Set(["Enter", "F2"])

function findCellIndex(cells, candidate) {
  return cells.findIndex(
    (cell) => cell.entryId === candidate.entryId && cell.scheme === candidate.scheme,
  )
}

export function shouldOpenEditor({ key, printable }) {
  if (OPEN_EDITOR_KEYS.has(key)) return true
  return key != null && key.length === 1 && printable === true
}

export function nextEditableCell({ cells, active, key, shiftKey = false }) {
  if (!Array.isArray(cells) || cells.length === 0 || !active) return null

  const currentIndex = findCellIndex(cells, active)
  if (currentIndex === -1) return null

  const delta = (() => {
    if (key === "Tab" && shiftKey) return -1
    if (key in GRID_ADVANCE_BY_KEY) return GRID_ADVANCE_BY_KEY[key]
    return 1
  })()

  const nextIndex = Math.max(0, Math.min(cells.length - 1, currentIndex + delta))
  return cells[nextIndex]
}

export function focusFallback({ cells, previous }) {
  if (!Array.isArray(cells) || cells.length === 0 || !previous) return null

  const exactMatch = findCellIndex(cells, previous)
  if (exactMatch >= 0) return cells[exactMatch]

  const sameScheme = cells
    .map((cell, index) => ({ cell, index }))
    .filter((entry) => entry.cell.scheme === previous.scheme)

  if (sameScheme.length === 0) return cells[0]

  if (typeof previous.index === "number" && Number.isInteger(previous.index)) {
    const preferred = sameScheme.findLast((entry) => entry.index <= previous.index)
    return preferred ? preferred.cell : sameScheme[0].cell
  }

  return sameScheme[0].cell
}
