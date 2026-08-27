export function parseTagNames(value) {
  const seen = new Set()

  return String(value)
    .split(",")
    .map((name) => name.trim())
    .filter((name) => {
      if (!name) return false

      const normalized = name.toLowerCase()
      if (seen.has(normalized)) return false

      seen.add(normalized)
      return true
    })
}

export function activeTagFragment(value) {
  return String(value).split(",").at(-1).trim()
}
