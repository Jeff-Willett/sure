export const EXPLORER_ARRAY_FILTER_KEYS = [
  "entity_ids",
  "years",
  "months",
  "types",
  "wdg_categories",
  "jpw_categories",
  "detail_category_ids",
  "wdg_rollup_ids",
  "include_tag_ids",
  "exclude_tag_ids",
];

const EXPLORER_SEARCH_KEY = "search";
const EMPTY_SENTINEL = "__none__";

export function explorerFiltersFromFormData(formData) {
  const filters = {};

  for (const key of EXPLORER_ARRAY_FILTER_KEYS) {
    const formKey = `${key}[]`;
    if (![...formData.keys()].includes(formKey)) continue;

    filters[key] = formData
      .getAll(formKey)
      .map(String)
      .filter((value) => value && value !== EMPTY_SENTINEL);
  }

  if ([...formData.keys()].includes(EXPLORER_SEARCH_KEY)) {
    filters.search = String(formData.get(EXPLORER_SEARCH_KEY) || "").trim();
  }

  return filters;
}

export function explorerFiltersFromSearch(search) {
  const params = new URLSearchParams(search);
  const filters = {};

  for (const key of EXPLORER_ARRAY_FILTER_KEYS) {
    const queryKey = `${key}[]`;
    if (!params.has(queryKey)) continue;

    filters[key] = params
      .getAll(queryKey)
      .filter((value) => value && value !== EMPTY_SENTINEL);
  }

  if (params.has(EXPLORER_SEARCH_KEY)) {
    filters.search = String(params.get(EXPLORER_SEARCH_KEY) || "").trim();
  }

  return filters;
}

export function explorerSearchFromFilters(filters) {
  const params = new URLSearchParams();

  for (const key of EXPLORER_ARRAY_FILTER_KEYS) {
    if (!Object.hasOwn(filters, key)) continue;

    const values = filters[key] || [];
    if (values.length === 0) {
      params.append(`${key}[]`, EMPTY_SENTINEL);
    } else {
      values.forEach((value) => params.append(`${key}[]`, String(value)));
    }
  }

  if (Object.hasOwn(filters, EXPLORER_SEARCH_KEY)) {
    params.set(EXPLORER_SEARCH_KEY, String(filters.search || "").trim());
  }

  const query = params.toString();
  return query ? `?${query}` : "";
}

export function hasExplorerFilterSearch(search) {
  const params = new URLSearchParams(search);

  return (
    params.has(EXPLORER_SEARCH_KEY) ||
    EXPLORER_ARRAY_FILTER_KEYS.some((key) => params.has(`${key}[]`))
  );
}

export function explorerPersistableFilters(filters) {
  const { search: _ignored, ...persistable } = filters;
  return persistable;
}
