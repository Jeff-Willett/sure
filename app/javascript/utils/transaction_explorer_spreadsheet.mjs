const SCHEMES = ["WDG", "JPW"];
const TABULATOR_FIELDS = ["detail_category", "tags"];

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

export function tabulatorSelectionRange(cells, anchor, focus, { lockField = false } = {}) {
  const rows = [...new Set(cells.map((cell) => cell.entryId))];
  const anchorRow = rows.indexOf(anchor?.entryId);
  const focusRow = rows.indexOf(focus?.entryId);
  const anchorColumn = TABULATOR_FIELDS.indexOf(anchor?.field);
  const focusColumn = lockField ? anchorColumn : TABULATOR_FIELDS.indexOf(focus?.field);
  if ([anchorRow, focusRow, anchorColumn, focusColumn].some((index) => index < 0)) return [];

  const rowStart = Math.min(anchorRow, focusRow);
  const rowEnd = Math.max(anchorRow, focusRow);
  const columnStart = Math.min(anchorColumn, focusColumn);
  const columnEnd = Math.max(anchorColumn, focusColumn);

  return cells.filter((cell) => {
    const row = rows.indexOf(cell.entryId);
    const column = TABULATOR_FIELDS.indexOf(cell.field);
    return row >= rowStart && row <= rowEnd && column >= columnStart && column <= columnEnd;
  });
}

export function tabulatorCopyPayload(selection) {
  if (!selection.length) throw new Error("Select at least one editable cell");

  const rows = [...new Set(selection.map((cell) => cell.entryId))];
  const fields = TABULATOR_FIELDS.filter((field) =>
    selection.some((cell) => cell.field === field),
  );
  const matrix = rows.map((entryId) =>
    fields.map((field) => {
      const cell = selection.find(
        (candidate) => candidate.entryId === entryId && candidate.field === field,
      );
      if (!cell) throw new Error("Selection must be rectangular");

      return field === "detail_category"
        ? { categoryId: cell.categoryId, label: cell.label }
        : { tagIds: [...cell.tagIds], label: cell.label };
    }),
  );

  return {
    text: matrix.map((row) => row.map(({ label }) => label).join("\t")).join("\n"),
    fields,
    rows: matrix,
  };
}

export function tabulatorPasteEdits({
  cells,
  selection,
  active,
  clipboard,
  resolveCategoryId = ({ source }) => source.categoryId,
  resolveTagIds = ({ source }) => source.tagIds,
}) {
  validateTabulatorClipboard(clipboard);
  const targets = pasteTargets({ cells, selection, active, clipboard });
  const edits = [];

  targets.forEach(({ cell, source, sourceField }) => {
    if (cell.field !== sourceField) {
      throw new Error(
        `${fieldLabel(sourceField)} cannot be pasted into ${fieldLabel(cell.field)}`,
      );
    }

    if (cell.field === "detail_category") {
      const categoryId = resolveCategoryId({ source, target: cell });
      if (!categoryId) throw new Error(`Unknown category: ${source.label}`);
      if (categoryId === cell.categoryId) return;
      edits.push({
        field: "detail_category",
        entryId: cell.entryId,
        schemeId: cell.schemeId,
        categoryId,
        expectedCategoryId: cell.categoryId,
      });
      return;
    }

    const tagIds = [...resolveTagIds({ source, target: cell })];
    if (sameValues(tagIds, cell.tagIds)) return;
    edits.push({
      field: "tags",
      entryId: cell.entryId,
      tagIds,
      expectedTagIds: [...cell.tagIds],
    });
  });

  return edits;
}

function validateTabulatorClipboard(clipboard) {
  const width = clipboard?.fields?.length;
  if (!width || !clipboard.rows?.length) throw new Error("Clipboard is empty");
  if (
    clipboard.fields.some((field) => !TABULATOR_FIELDS.includes(field)) ||
    clipboard.rows.some((row) => row.length !== width)
  ) {
    throw new Error("Clipboard must be a rectangular editable-cell range");
  }
}

function pasteTargets({ cells, selection, active, clipboard }) {
  if (!active) throw new Error("Paste target is unavailable");
  const sourceHeight = clipboard.rows.length;
  const sourceWidth = clipboard.fields.length;

  if (sourceHeight === 1 && sourceWidth === 1 && selection.length > 1) {
    return selection.map((cell) => ({
      cell,
      source: clipboard.rows[0][0],
      sourceField: clipboard.fields[0],
    }));
  }

  const rows = [...new Set(cells.map((cell) => cell.entryId))];
  const anchorRow = rows.indexOf(active.entryId);
  const anchorColumn = TABULATOR_FIELDS.indexOf(active.field);
  if (
    anchorRow < 0 ||
    anchorColumn < 0 ||
    anchorRow + sourceHeight > rows.length ||
    anchorColumn + sourceWidth > TABULATOR_FIELDS.length
  ) {
    throw new Error("Paste range exceeds the editable grid");
  }

  if (selection.length > 1 && selection.length !== sourceHeight * sourceWidth) {
    throw new Error("Paste range must match the selected range");
  }

  return clipboard.rows.flatMap((sourceRow, rowOffset) =>
    sourceRow.map((source, columnOffset) => {
      const field = TABULATOR_FIELDS[anchorColumn + columnOffset];
      const cell = cells.find(
        (candidate) =>
          candidate.entryId === rows[anchorRow + rowOffset] &&
          candidate.field === field,
      );
      if (!cell) throw new Error("Paste target is unavailable");
      return {
        cell,
        source,
        sourceField: clipboard.fields[columnOffset],
      };
    }),
  );
}

function fieldLabel(field) {
  return field === "detail_category" ? "Detail category" : "Tags";
}

function sameValues(left, right) {
  return [...left].map(String).sort().join("\u0000") ===
    [...right].map(String).sort().join("\u0000");
}

function editFor(cell, categoryId) {
  return {
    entryId: cell.entryId,
    scheme: cell.scheme,
    categoryId,
    expectedCategoryId: cell.categoryId || null,
  };
}
