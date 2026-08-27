const TYPE_ORDER = new Map([
  ["Expense", 0],
  ["Refund", 1],
  ["Income", 2],
  ["Transfer", 3],
]);
const EMPTY_SET = new Set();
const DECIMAL_SCALE = 10_000n;

export function deriveExplorerReport(
  dataset,
  filters = {},
  { rollupMode = "wdg" } = {},
) {
  const preparedFilters = prepareFilters(filters);
  const entityRows = classifyRefunds(
    selectEntityAmounts(dataset, preparedFilters),
  );
  const rows = filterRows(entityRows, preparedFilters);

  return {
    rows,
    metrics: buildMetrics(rows),
    rollup: buildRollup(rows, rollupMode),
    availability: buildAvailability(entityRows, preparedFilters),
  };
}

function selectEntityAmounts(dataset, filters) {
  const explicit = hasFilter(filters, "entity_ids");
  const selected = selectedSet(filters, "entity_ids");
  if (explicit && selected.size === 0) return [];

  return dataset.flatMap((row) => {
    const amounts = Object.entries(row.entity_amounts || {});
    const selectedAmounts = explicit
      ? amounts.filter(([entityId]) => selected.has(String(entityId)))
      : amounts;
    if (selectedAmounts.length === 0) return [];

    const amountUnits = selectedAmounts.reduce(
      (total, [, entityAmount]) => total + decimalToUnits(entityAmount),
      0n,
    );
    const amountExact = unitsToDecimalString(amountUnits);
    const amount = Number(amountExact);
    const type = row.transfer
      ? "Transfer"
      : amountUnits > 0n
        ? "Income"
        : "Expense";

    return [
      {
        ...row,
        amount,
        amount_exact: amountExact,
        entity_ids: selectedAmounts.map(([entityId]) => String(entityId)),
        entity: selectedAmounts
          .map(([entityId]) => row.entity_labels?.[entityId])
          .filter(Boolean)
          .sort()
          .join(", "),
        type,
      },
    ];
  });
}

function classifyRefunds(rows) {
  const expenseCategoryIds = new Set(
    rows
      .filter(({ type, detail_category_id }) =>
        type === "Expense" && detail_category_id != null,
      )
      .map(({ detail_category_id }) => String(detail_category_id)),
  );

  return rows.map((row) => {
    const expenseCredit =
      row.type === "Income" &&
      row.detail_category_id != null &&
      expenseCategoryIds.has(String(row.detail_category_id)) &&
      (row.wdg_rollup || row.wdg) !== "Transfer";

    return expenseCredit ? { ...row, type: "Refund" } : row;
  });
}

function filterRows(rows, filters, excludedKey = null, sort = true) {
  const filtered = rows
    .filter((row) =>
      excludedKey === "years" || matchesRequired(filters, "years", year(row)),
    )
    .filter((row) =>
      excludedKey === "months" || matchesRequired(filters, "months", month(row)),
    )
    .filter((row) =>
      excludedKey === "types" || matchesType(filters, row.type),
    )
    .filter((row) =>
      excludedKey === "wdg_categories" ||
      matchesRequired(filters, "wdg_categories", row.wdg),
    )
    .filter((row) =>
      excludedKey === "jpw_categories" ||
      matchesRequired(filters, "jpw_categories", row.jpw),
    )
    .filter((row) =>
      excludedKey === "detail_category_ids" ||
      matchesRequired(filters, "detail_category_ids", row.detail_category_id),
    )
    .filter((row) =>
      excludedKey === "wdg_rollup_ids" ||
      matchesOptional(filters, "wdg_rollup_ids", row.wdg_rollup_id),
    )
    .filter((row) =>
      excludedKey === "include_tag_ids" || matchesIncludedTags(filters, row),
    )
    .filter((row) =>
      excludedKey === "exclude_tag_ids" || !matchesExcludedTags(filters, row),
    )
    .filter((row) => matchesSearch(filters, row));

  return sort
    ? filtered.sort(
        (left, right) =>
          right.date.localeCompare(left.date) ||
          String(left.id).localeCompare(String(right.id)),
      )
    : filtered;
}

function matchesRequired(filters, key, value) {
  if (!hasFilter(filters, key)) return true;
  if (value == null) return false;

  return selectedSet(filters, key).has(String(value));
}

function matchesOptional(filters, key, value) {
  if (!hasFilter(filters, key)) return true;
  const selected = selectedSet(filters, key);
  if (selected.size === 0) return true;
  if (value == null) return false;

  return selected.has(String(value));
}

function matchesType(filters, type) {
  if (!hasFilter(filters, "types")) return true;
  const selected = selectedSet(filters, "types");
  if (type === "Refund") {
    return selected.has("Expense") || selected.has("Refund");
  }

  return selected.has(type);
}

function matchesIncludedTags(filters, row) {
  if (!hasFilter(filters, "include_tag_ids")) return true;
  const selected = selectedSet(filters, "include_tag_ids");
  if (selected.size === 0) return true;

  return (row.tag_ids || []).some((tagId) => selected.has(String(tagId)));
}

function matchesExcludedTags(filters, row) {
  const selected = selectedSet(filters, "exclude_tag_ids");
  if (selected.size === 0) return false;

  return (row.tag_ids || []).some((tagId) => selected.has(String(tagId)));
}

function matchesSearch(filters, row) {
  const search = String(filters.values.search || "")
    .trim()
    .toLowerCase();
  if (!search) return true;

  return [
    row.description,
    row.account,
    row.wdg,
    row.jpw,
    row.detail_category,
    row.wdg_rollup,
    row.entity,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase()
    .includes(search);
}

function buildMetrics(rows) {
  const expenseRows = rows.filter(({ type }) => type === "Expense");
  const refundRows = rows.filter(({ type }) => type === "Refund");

  return {
    transactions: rows.length,
    expenses: unitsToNumber(
      sumUnits(expenseRows, (row) => absoluteDecimal(exactAmount(row))) -
        sumUnits(refundRows, exactAmount),
    ),
    income: unitsToNumber(
      sumUnits(
        rows.filter(({ type }) => type === "Income"),
        exactAmount,
      ),
    ),
    transfer_net: unitsToNumber(
      sumUnits(
        rows.filter(({ type }) => type === "Transfer"),
        exactAmount,
      ),
    ),
  };
}

function buildRollup(rows, rollupMode) {
  return groupBy(rows, ({ type }) => (type === "Refund" ? "Expense" : type))
    .map(([type, typeRows]) => ({
      type,
      amount: unitsToNumber(sumUnits(typeRows, exactAmount)),
      groups:
        rollupMode === "wdg"
          ? buildWdgGroups(typeRows)
          : buildEntityGroups(typeRows),
    }))
    .sort(
      (left, right) =>
        (TYPE_ORDER.get(left.type) ?? 99) - (TYPE_ORDER.get(right.type) ?? 99),
    );
}

function buildWdgGroups(rows) {
  return groupBy(rows, (row) => [
    row.wdg_rollup_id || row.wdg_category_id,
    row.wdg_rollup || row.wdg,
  ])
    .map(([[rollupId, label], groupRows]) => ({
      wdg: label,
      entity_id: null,
      wdg_rollup_id: rollupId,
      amount: unitsToNumber(sumUnits(groupRows, exactAmount)),
      categories: buildCategories(groupRows),
    }))
    .sort(byAbsoluteAmountThen("wdg"));
}

function buildEntityGroups(rows) {
  return groupBy(rows, (row) => [row.entity_id, row.entity_name || "Needs entity"])
    .map(([[entityId, label], groupRows]) => ({
      wdg: label,
      entity_id: entityId,
      wdg_rollup_id: null,
      amount: unitsToNumber(sumUnits(groupRows, exactAmount)),
      categories: buildCategories(groupRows),
    }))
    .sort(byAbsoluteAmountThen("wdg"));
}

function buildCategories(rows) {
  return groupBy(rows, (row) => [
    row.detail_category_id || row.jpw_category_id,
    row.detail_category || row.jpw,
  ])
    .map(([[categoryId, label], categoryRows]) => ({
      jpw: label,
      detail_category_id: categoryId,
      amount: unitsToNumber(sumUnits(categoryRows, exactAmount)),
      count: categoryRows.length,
    }))
    .sort(byAbsoluteAmountThen("jpw"));
}

function buildAvailability(rows, filters) {
  return {
    wdg_categories: unique(
      filterRows(rows, filters, "wdg_categories", false).map(({ wdg }) => wdg),
    ),
    jpw_categories: unique(
      filterRows(rows, filters, "jpw_categories", false).map(({ jpw }) => jpw),
    ),
    detail_category_ids: unique(
      filterRows(rows, filters, "detail_category_ids", false)
        .map(({ detail_category_id }) => detail_category_id)
        .filter((value) => value != null),
    ),
    wdg_rollup_ids: unique(
      filterRows(rows, filters, "wdg_rollup_ids", false)
        .map(({ wdg_rollup_id }) => wdg_rollup_id)
        .filter((value) => value != null),
    ),
    tag_ids: unique(
      filterRows(rows, filters, "include_tag_ids", false).flatMap(
        ({ tag_ids }) => tag_ids || [],
      ),
    ),
  };
}

function groupBy(values, keyFor) {
  const groups = new Map();
  for (const value of values) {
    const key = keyFor(value);
    const mapKey = Array.isArray(key) ? JSON.stringify(key) : String(key);
    const existing = groups.get(mapKey);
    if (existing) {
      existing[1].push(value);
    } else {
      groups.set(mapKey, [key, [value]]);
    }
  }
  return [...groups.values()];
}

function selectedSet(filters, key) {
  return filters.sets[key] || EMPTY_SET;
}

function hasFilter(filters, key) {
  return Object.hasOwn(filters.values, key);
}

function prepareFilters(filters) {
  return {
    values: filters,
    sets: Object.fromEntries(
      Object.entries(filters)
        .filter(([, value]) => Array.isArray(value))
        .map(([key, value]) => [key, new Set(value.map(String))]),
    ),
  };
}

function year(row) {
  return row.date.slice(0, 4);
}

function month(row) {
  return String(Number(row.date.slice(5, 7)));
}

function exactAmount(row) {
  return row.amount_exact ?? row.amount;
}

function absoluteDecimal(value) {
  return String(value).replace(/^-/, "");
}

function sumUnits(values, mapper) {
  return values.reduce(
    (total, value) => total + decimalToUnits(mapper(value)),
    0n,
  );
}

function decimalToUnits(value) {
  const text = String(value).trim();
  const negative = text.startsWith("-");
  const unsigned = text.replace(/^[+-]/, "");
  const [whole = "0", fraction = ""] = unsigned.split(".");
  const scaledFraction = `${fraction}0000`.slice(0, 4);
  const units = BigInt(whole || "0") * DECIMAL_SCALE + BigInt(scaledFraction);
  return negative ? -units : units;
}

function unitsToDecimalString(units) {
  const negative = units < 0n;
  const absolute = negative ? -units : units;
  const whole = absolute / DECIMAL_SCALE;
  const fraction = String(absolute % DECIMAL_SCALE)
    .padStart(4, "0")
    .replace(/0+$/, "");
  return `${negative ? "-" : ""}${whole}${fraction ? `.${fraction}` : ""}`;
}

function unitsToNumber(units) {
  return Number(unitsToDecimalString(units));
}

function unique(values) {
  return [...new Set(values.map(String))].sort();
}

function byAbsoluteAmountThen(labelKey) {
  return (left, right) =>
    Math.abs(right.amount) - Math.abs(left.amount) ||
    String(left[labelKey] || "").localeCompare(String(right[labelKey] || ""));
}
