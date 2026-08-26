export const TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY =
  "transaction-explorer:column-widths:v1"

export const TRANSACTION_EXPLORER_COLUMNS = {
  date: { defaultWidth: 140, minWidth: 96 },
  entity: { defaultWidth: 260, minWidth: 180 },
  catalog: { defaultWidth: 120, minWidth: 96 },
  wdg_rollup: { defaultWidth: 180, minWidth: 140 },
  detail_category: { defaultWidth: 180, minWidth: 140 },
  tags: { defaultWidth: 240, minWidth: 180 },
  wdg: { defaultWidth: 180, minWidth: 140 },
  jpw: { defaultWidth: 180, minWidth: 140 },
  description: { defaultWidth: 360, minWidth: 220 },
  account: { defaultWidth: 220, minWidth: 160 },
  amount: { defaultWidth: 150, minWidth: 120 },
}

const toPositiveInteger = (value) => {
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : null
}

const defaultWidths = () =>
  Object.fromEntries(
    Object.entries(TRANSACTION_EXPLORER_COLUMNS).map(
      ([key, config]) => [key, config.defaultWidth],
    ),
  )

export function deriveDesktopStickyOffsets(widths = defaultWidths()) {
  return {
    date: 0,
    entity: widths.date ?? TRANSACTION_EXPLORER_COLUMNS.date.defaultWidth,
  }
}

export function clampWidth(column, width) {
  const config = TRANSACTION_EXPLORER_COLUMNS[column]
  if (!config) {
    throw new Error(`Unknown transaction explorer column: ${column}`)
  }

  const parsed = toPositiveInteger(width)
  if (parsed === null) return config.defaultWidth

  return Math.max(config.minWidth, parsed)
}

export function resizeWidths(current, column, delta) {
  if (!current) return current

  const config = TRANSACTION_EXPLORER_COLUMNS[column]
  if (!config) {
    throw new Error(`Unknown transaction explorer column: ${column}`)
  }

  const currentWidth = current[column] ?? config.defaultWidth
  const nextWidth = clampWidth(column, toPositiveInteger(currentWidth) + delta)

  return {
    ...current,
    [column]: nextWidth,
  }
}

export function resetWidth(column) {
  const config = TRANSACTION_EXPLORER_COLUMNS[column]
  if (!config) {
    throw new Error(`Unknown transaction explorer column: ${column}`)
  }

  return config.defaultWidth
}

export function parseStoredWidths(json) {
  if (json === null || json === undefined) return defaultWidths()

  let raw
  try {
    raw = JSON.parse(json)
  } catch (error) {
    throw new Error(`Malformed transaction explorer column width data: ${error.message}`)
  }

  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("Malformed transaction explorer column width data")
  }

  const keys = Object.keys(raw)
  const known = Object.keys(TRANSACTION_EXPLORER_COLUMNS)
  const unknown = keys.filter((key) => !known.includes(key))
  if (unknown.length > 0) {
    throw new Error(`Unknown transaction explorer column: ${unknown.join(", ")}`)
  }

  const invalid = Object.entries(raw).find(
    ([, width]) => typeof width !== "number" || !Number.isFinite(width),
  )
  if (invalid) {
    throw new Error(`Malformed transaction explorer column width data`)
  }

  return {
    ...defaultWidths(),
    ...Object.fromEntries(
      Object.entries(raw).map(([column, width]) => [
        column,
        clampWidth(column, width),
      ]),
    ),
  }
}
