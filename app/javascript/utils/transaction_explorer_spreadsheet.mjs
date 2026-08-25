const SCHEMES = ["WDG", "JPW"];

export function selectionRange(cells, anchor, focus) {
  const rows = [...new Set(cells.map((cell) => cell.entryId))];
  const anchorRow = rows.indexOf(anchor?.entryId);
  const focusRow = rows.indexOf(focus?.entryId);
  const anchorColumn = SCHEMES.indexOf(anchor?.scheme);
  const focusColumn = SCHEMES.indexOf(focus?.scheme);
  if ([anchorRow, focusRow, anchorColumn, focusColumn].some((index) => index < 0)) return [];

  const rowStart = Math.min(anchorRow, focusRow);
  const rowEnd = Math.max(anchorRow, focusRow);
  const columnStart = Math.min(anchorColumn, focusColumn);
  const columnEnd = Math.max(anchorColumn, focusColumn);

  return cells.filter((cell) => {
    const row = rows.indexOf(cell.entryId);
    const column = SCHEMES.indexOf(cell.scheme);
    return row >= rowStart && row <= rowEnd && column >= columnStart && column <= columnEnd;
  });
}

export function parseClipboardText(text) {
  if (typeof text !== "string" || text.trim() === "") throw new Error("Clipboard is empty");
  const matrix = text
    .replaceAll("\r\n", "\n")
    .trim()
    .split("\n")
    .map((row) => row.split("\t").map((value) => value.trim()));
  const width = matrix[0].length;
  if (width < 1 || width > SCHEMES.length || matrix.some((row) => row.length !== width || row.some((value) => !value))) {
    throw new Error("Clipboard must be a rectangular category range");
  }
  return matrix;
}

export function pasteEdits({ cells, target, matrix, categories }) {
  const rows = [...new Set(cells.map((cell) => cell.entryId))];
  const targetRow = rows.indexOf(target?.entryId);
  const targetColumn = SCHEMES.indexOf(target?.scheme);
  if (targetRow < 0 || targetColumn < 0) throw new Error("Paste target is unavailable");
  if (targetRow + matrix.length > rows.length || targetColumn + matrix[0].length > SCHEMES.length) {
    throw new Error("Paste range exceeds the editable grid");
  }

  return matrix.flatMap((values, rowOffset) =>
    values.flatMap((name, columnOffset) => {
      const scheme = SCHEMES[targetColumn + columnOffset];
      const cell = cells.find((candidate) => candidate.entryId === rows[targetRow + rowOffset] && candidate.scheme === scheme);
      const categoryId = categories[scheme]?.get(name);
      if (!categoryId) throw new Error(`Unknown ${scheme} category: ${name}`);
      if (!cell || cell.categoryId === categoryId) return [];
      return [ editFor(cell, categoryId) ];
    }),
  );
}

export function fillDownEdits({ cells, selection }) {
  const rows = [...new Set(selection.map((cell) => cell.entryId))];
  if (rows.length < 2) throw new Error("Select at least two rows to fill down");
  const sourceRow = rows[0];
  const schemes = [...new Set(selection.map((cell) => cell.scheme))];

  return rows.slice(1).flatMap((entryId) =>
    schemes.flatMap((scheme) => {
      const source = selection.find((cell) => cell.entryId === sourceRow && cell.scheme === scheme);
      const target = selection.find((cell) => cell.entryId === entryId && cell.scheme === scheme);
      if (!source || !target || !source.categoryId || source.categoryId === target.categoryId) return [];
      return [ editFor(target, source.categoryId) ];
    }),
  );
}

function editFor(cell, categoryId) {
  return {
    entryId: cell.entryId,
    scheme: cell.scheme,
    categoryId,
    expectedCategoryId: cell.categoryId || null,
  };
}
