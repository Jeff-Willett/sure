import { Controller } from "@hotwired/stimulus";
import { TabulatorFull as Tabulator } from "tabulator-tables";
import { parseTagNames } from "utils/tag_input";
import {
  explorerFiltersFromFormData,
  explorerFiltersFromSearch,
  explorerPersistableFilters,
  explorerSearchFromFilters,
  hasExplorerFilterSearch,
} from "utils/transaction_explorer_history";
import { deriveExplorerReport } from "utils/transaction_explorer_report";
import {
  TRANSACTION_EXPLORER_VIEW_STATE_KEY,
  parseExplorerViewState,
  serializeExplorerViewState,
} from "utils/transaction_explorer_view_state";

export default class extends Controller {
  static targets = [
    "categoryData",
    "count",
    "data",
    "exclusionBanner",
    "form",
    "grid",
    "layoutMenu",
    "rollupButton",
    "rollupContent",
    "rollupPane",
    "sort",
    "tagData",
  ];
  static values = {
    createTagUrl: String,
    currency: String,
    defaultFilters: Object,
    emptyMessage: String,
    excludedTagsTemplate: String,
    filterStorageKey: String,
    persistenceId: String,
    rollupMode: String,
    showingTemplate: String,
    subunit: Number,
    uncategorizedLabel: String,
    workingDataUrl: String,
  };

  connect() {
    this.connected = true;
    const loadToken = Symbol("transaction-explorer-load");
    this.loadToken = loadToken;
    this.tableStateRestored = false;
    this.restoredPersistedFilters = false;
    this.workingDataAbortController = new AbortController();
    this.viewState = this.loadViewState();
    this.moneyFormatter = new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: this.currencyValue,
    });
    this.listFormatter = new Intl.ListFormat(undefined, {
      style: "long",
      type: "conjunction",
    });
    this.element.dataset.layoutMode = this.viewState.layout;
    this.restoreRollups();
    this.categoryOptions = JSON.parse(
      this.categoryDataTarget.content.textContent,
    );
    this.tagCatalog = JSON.parse(this.tagDataTarget.content.textContent);
    this.initialRows = JSON.parse(
      this.dataTarget.content?.textContent || this.dataTarget.textContent,
    );
    this.defaultFilters = this.defaultFiltersValue;
    const initialFilters = this.initialFilters();
    this.implicitAllDetailCategories = !Object.hasOwn(
      initialFilters,
      "detail_category_ids",
    );
    this.syncForm(initialFilters);
    if (this.restoredPersistedFilters) {
      this.updateHistory(initialFilters, "replace");
    }
    this.currentReport = null;
    this.tableReadyPromise = new Promise((resolve) => {
      this.resolveTableReady = resolve;
    });
    this.table = new Tabulator(this.gridTarget, {
      data: this.initialRows,
      index: "id",
      layout: this.viewState.layout,
      height: "100%",
      movableColumns: true,
      selectableRows: true,
      selectableRowsRangeMode: "drag",
      clipboard: true,
      clipboardCopyRowRange: "selected",
      history: true,
      groupBy: "entity",
      groupStartOpen: true,
      persistence: { sort: true, group: true },
      persistenceMode: "local",
      persistenceID: this.persistenceIdValue,
      rowHeader: {
        formatter: "rowSelection",
        titleFormatter: "rowSelection",
        frozen: true,
        headerSort: false,
        width: 42,
        hozAlign: "center",
      },
      initialSort: [{ column: "date", dir: "desc" }],
      columns: this.columns,
    });
    this.table.on("tableBuilt", () => this.restoreTableState());
    setTimeout(() => this.restoreTableState(), 0);
    this.table.on("columnMoved", () => this.persistViewState());
    this.table.on("columnResized", () => this.persistViewState());
    this.table.on("columnVisibilityChanged", () => this.persistViewState());
    this.onPopState = () => this.restoreHistoryState();
    window.addEventListener("popstate", this.onPopState);
    this.loadingPromise = this.loadWorkingRows(initialFilters, loadToken);
  }

  disconnect() {
    this.connected = false;
    this.loadToken = null;
    this.workingDataAbortController.abort();
    this.resolveTableReady?.();
    this.resolveTableReady = null;
    clearTimeout(this.searchTimeout);
    window.removeEventListener("popstate", this.onPopState);
    this.persistViewState();
    this.table?.destroy();
    this.table = null;
  }

  get columns() {
    return [
      { title: "Status", field: "workflow_status", frozen: true, width: 118 },
      { title: "Type", field: "type", frozen: true, width: 90 },
      {
        title: "Date",
        field: "date",
        frozen: true,
        width: 105,
        sorter: "string",
      },
      { title: "Entity", field: "entity", frozen: true, width: 76 },
      {
        title: "WDG rollup",
        field: "wdg_rollup",
        width: 190,
        formatter: (cell) => cell.getRow().getData().wdg_rollup_display,
        accessorClipboard: (_value, data) => data.wdg_rollup_display,
      },
      {
        title: "Detail category",
        field: "detail_category_id",
        width: 180,
        formatter: (cell) => cell.getRow().getData().detail_category,
        accessorClipboard: (_value, data) => data.detail_category,
        editable: (cell) => cell.getRow().getData().editable,
        editor: "list",
        editorParams: (cell) => ({
          values: this.categoryValues(cell.getRow().getData().detail_scheme),
          autocomplete: true,
          allowEmpty: true,
          clearable: true,
          listOnEmpty: true,
        }),
        cellEdited: (cell) => this.saveCategory(cell),
      },
      {
        title: "Tags",
        field: "tags",
        width: 220,
        editable: (cell) => cell.getRow().getData().editable,
        editor: "list",
        editorParams: () => ({
          values: this.tagCatalog.map((tag) => tag.name),
          autocomplete: true,
          allowEmpty: true,
          clearable: true,
          freetext: true,
          listOnEmpty: true,
        }),
        cellEdited: (cell) => this.saveTags(cell),
      },
      { title: "Description", field: "description", width: 360 },
      { title: "Account", field: "account", width: 220 },
      {
        title: "Amount",
        field: "amount",
        width: 140,
        hozAlign: "right",
        sorter: "number",
        formatter: this.amountFormatter,
      },
    ];
  }

  amountFormatter(cell) {
    const span = document.createElement("span");
    span.textContent = cell.getRow().getData().amount_display;
    span.className = cell.getValue() < 0 ? "text-destructive" : "text-success";
    return span;
  }

  categoryValues(scheme) {
    return Object.fromEntries(
      (this.categoryOptions[scheme] || []).map(([id, name]) => [id, name]),
    );
  }

  async saveCategory(cell) {
    await this.loadingPromise;
    const row = cell.getRow();
    const data = row.getData();
    const previousId = cell.getOldValue();
    const nextId = cell.getValue();
    const body = new URLSearchParams({
      scheme_id: data.scheme_id || "",
      category_id: nextId || "",
      expected_category_id: previousId || "",
    });
    const response = await fetch(data.category_update_url, {
      method: "PATCH",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        "X-CSRF-Token": this.csrfToken,
      },
      body,
      credentials: "same-origin",
    });

    if (!response.ok) {
      cell.setValue(previousId, true);
      return;
    }

    const payload = await response.json();
    this.patchWorkingRow(payload.row);
    await this.applyCurrentFilters({ historyAction: null });
  }

  async saveTags(cell) {
    await this.loadingPromise;
    const row = cell.getRow();
    const data = row.getData();
    const ids = [];

    for (const name of parseTagNames(cell.getValue())) {
      let tag = this.tagCatalog.find(
        (candidate) => candidate.name.toLowerCase() === name.toLowerCase(),
      );
      if (!tag) tag = await this.createTag(name);
      if (tag) ids.push(tag.id);
    }

    const response = await fetch(data.tag_update_url, {
      method: "PATCH",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
      },
      body: JSON.stringify({ tag_ids: ids }),
      credentials: "same-origin",
    });

    if (!response.ok) {
      cell.setValue(cell.getOldValue(), true);
      return;
    }

    const payload = await response.json();
    const authoritativeIds = (payload.tag_ids || []).map(String);
    const authoritativeNames = authoritativeIds
      .map((id) => this.tagCatalog.find((tag) => String(tag.id) === id)?.name)
      .filter(Boolean);
    this.patchWorkingRow({
      id: data.id,
      tag_ids: authoritativeIds,
      tags: authoritativeNames.join(", "),
    });
    await this.applyCurrentFilters({ historyAction: null });
  }

  async createTag(name) {
    const response = await fetch(this.createTagUrlValue, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
      },
      body: JSON.stringify({ tag: { name, color: "#e99537" } }),
      credentials: "same-origin",
    });
    if (!response.ok) return null;

    const created = await response.json();
    const tag = { id: String(created.id), name: created.name };
    this.tagCatalog.push(tag);
    return tag;
  }

  patchWorkingRow(patch) {
    if (!patch || !this.workingRows) return;
    const index = this.workingRows.findIndex(({ id }) => id === patch.id);
    if (index < 0) return;

    this.workingRows[index] = { ...this.workingRows[index], ...patch };
  }

  filterSubmitted(event) {
    event.preventDefault();
    this.applyCurrentFilters();
  }

  filterChanged(event) {
    if (event.target.name === "detail_category_ids[]") {
      this.implicitAllDetailCategories = false;
    }
    clearTimeout(this.searchTimeout);
    this.applyCurrentFilters();
  }

  searchChanged(event) {
    if (event.target.type !== "search") return;

    clearTimeout(this.searchTimeout);
    this.searchTimeout = setTimeout(() => this.applyCurrentFilters(), 20);
  }

  slicerChanged(event) {
    if (event.detail.key === "detail_category_ids") {
      this.implicitAllDetailCategories = false;
    }
  }

  resetFilters(event) {
    event.preventDefault();
    this.clearPersistedFilters();
    this.implicitAllDetailCategories = true;
    this.syncForm(this.defaultFilters, { clearMissing: true });
    this.applyCurrentFilters();
  }

  drillDown(event) {
    const link = event.currentTarget;
    const key = link.dataset.explorerFilterKey;
    const value = link.dataset.explorerFilterValue;
    if (!key || !value) return;

    event.preventDefault();
    if (key === "detail_category_ids") {
      this.implicitAllDetailCategories = false;
    }
    this.setFilterSelection(key, [value]);
    this.applyCurrentFilters();
  }

  async applyCurrentFilters({ historyAction = "push" } = {}) {
    await this.loadingPromise;
    if (!this.connected) return;
    if (!this.workingRows) {
      this.navigateToServer();
      return;
    }

    const filters = this.filtersFromForm();
    const filterSearch = explorerSearchFromFilters(filters);
    if (historyAction && filterSearch === this.currentFilterSearch) return;
    const report = deriveExplorerReport(this.workingRows, filters, {
      rollupMode: this.rollupModeValue,
    });

    this.visibleIds = new Set(report.rows.map(({ id }) => id));
    if (report.rows.length > 0) {
      await this.table.updateData(this.displayRows(report.rows));
    }
    this.table.setFilter(this.explorerRowFilter);
    this.currentReport = report;
    this.currentFilterSearch = filterSearch;
    this.renderReport(report);
    this.persistFilters(filters);
    this.updateHistory(filters, historyAction);
  }

  renderReport(report) {
    this.countTarget.textContent = this.showingTemplateValue
      .replace("__SHOWN__", String(report.rows.length))
      .replace("__TOTAL__", String(report.rows.length));
    this.renderRollup(report.rollup);
    this.updateFilterAvailability(report.availability);
    this.updateExclusionBanner();
  }

  async loadWorkingRows(initialFilters, loadToken) {
    this.formTarget.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(this.workingDataUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        signal: this.workingDataAbortController.signal,
      });
      if (this.loadToken !== loadToken) return;
      if (!response.ok)
        throw new Error(`Working set request failed: ${response.status}`);

      const payload = await response.json();
      if (!this.connected || this.loadToken !== loadToken) return;
      if (payload.fallback) {
        this.workingRows = null;
        return;
      }
      this.workingRows = payload.rows;
      this.currentReport = deriveExplorerReport(
        this.workingRows,
        initialFilters,
        { rollupMode: this.rollupModeValue },
      );
      this.currentFilterSearch = explorerSearchFromFilters(initialFilters);
      await this.tableReadyPromise;
      if (!this.connected || this.loadToken !== loadToken) return;
      this.visibleIds = new Set(this.currentReport.rows.map(({ id }) => id));
      this.explorerRowFilter = ({ id }) => this.visibleIds.has(id);
      const selectedIds = this.table.getSelectedData().map(({ id }) => id);
      await this.table.replaceData(this.displayRows(this.workingRows));
      if (this.currentReport.rows.length > 0) {
        await this.table.updateData(this.displayRows(this.currentReport.rows));
      }
      this.table.setFilter(this.explorerRowFilter);
      this.table.selectRow(selectedIds.filter((id) => this.visibleIds.has(id)));
      this.renderReport(this.currentReport);
    } catch (error) {
      if (this.loadToken !== loadToken) return;
      this.workingRows = null;
      if (error.name !== "AbortError") {
        console.error("Transaction Explorer working set unavailable", error);
      }
    } finally {
      if (this.connected && this.loadToken === loadToken) {
        this.formTarget.removeAttribute("aria-busy");
      }
    }
  }

  navigateToServer() {
    const search = explorerSearchFromFilters(this.filtersFromForm());
    window.Turbo?.visit(`${window.location.pathname}${search}`, {
      action: "replace",
    });
  }

  displayRows(rows) {
    return rows.map((row) => ({
      ...row,
      amount_display: this.formatMoney(row.amount),
    }));
  }

  formatMoney(amount) {
    return this.moneyFormatter.format(Number(amount) / this.subunitValue);
  }

  renderRollup(rollup) {
    this.rollupContentTarget.replaceChildren();
    if (rollup.length === 0) {
      const empty = document.createElement("p");
      empty.className = "py-8 text-center text-sm text-secondary";
      empty.textContent = this.emptyMessageValue;
      this.rollupContentTarget.appendChild(empty);
      return;
    }

    rollup.forEach((type) => {
      const section = document.createElement("section");
      const header = document.createElement("div");
      header.className =
        "flex items-center justify-between px-1 pb-1.5 text-sm font-semibold text-primary";
      const label = document.createElement("span");
      const tones = this.rollupTones(type.type);
      label.className = `inline-flex min-h-7 items-center rounded-md px-2 py-1 text-xs font-semibold ${tones.label}`;
      label.textContent = type.type;
      const total = document.createElement("span");
      total.className = `tabular-nums ${tones.total}`;
      total.textContent = this.formatMoney(Math.abs(type.amount));
      header.append(label, total);
      section.appendChild(header);

      type.groups.forEach((group) => {
        const groupLink = this.rollupLink(
          group.wdg,
          group.amount,
          this.rollupModeValue === "wdg" ? "wdg_rollup_ids" : "entity_ids",
          this.rollupModeValue === "wdg"
            ? group.wdg_rollup_id
            : group.entity_id,
          "flex items-start justify-between gap-3 rounded-md px-2.5 py-2 text-sm font-medium text-primary transition-colors hover:bg-container-inset",
        );
        section.appendChild(groupLink);

        group.categories.forEach((category) => {
          section.appendChild(
            this.rollupLink(
              category.jpw,
              category.amount,
              "detail_category_ids",
              category.detail_category_id || "__uncategorized__",
              "flex items-start justify-between gap-3 rounded-md px-3 py-1.5 text-xs text-secondary transition-colors hover:bg-surface-hover hover:text-primary",
              this.rollupEmoji(category.jpw),
            ),
          );
        });
      });

      this.rollupContentTarget.appendChild(section);
    });
  }

  rollupLink(label, amount, key, value, className, emoji = null) {
    const link = document.createElement("a");
    link.href = this.filterUrl(key, value);
    link.className = className;
    link.dataset.action = "transaction-explorer-tabulator#drillDown";
    link.dataset.explorerFilterKey = key;
    link.dataset.explorerFilterValue = value || "";
    const name = document.createElement("span");
    name.className = emoji ? "inline-flex min-w-0 items-center gap-1.5" : "";
    if (emoji) {
      const icon = document.createElement("span");
      icon.className = "w-5 shrink-0 text-center text-sm leading-none";
      icon.setAttribute("aria-hidden", "true");
      icon.textContent = emoji;
      name.appendChild(icon);
    }
    const nameText = document.createElement("span");
    nameText.textContent = label || this.uncategorizedLabelValue;
    name.appendChild(nameText);
    const total = document.createElement("span");
    total.className = "tabular-nums";
    total.textContent = this.formatMoney(Math.abs(amount));
    link.append(name, total);
    return link;
  }

  rollupTones(type) {
    return (
      {
        Expense: {
          label: "bg-red-tint-10 text-destructive",
          total: "text-destructive",
        },
        Income: {
          label: "bg-green-tint-10 text-success",
          total: "text-success",
        },
        Transfer: {
          label: "bg-blue-tint-10 text-info",
          total: "text-info",
        },
      }[type] || {
        label: "bg-container-inset text-primary",
        total: "text-primary",
      }
    );
  }

  rollupEmoji(label) {
    const rules = [
      [/camp/i, "🏕️"],
      [/\brv\b/i, "🚐"],
      [/grocer/i, "🛒"],
      [/shopping/i, "🛍️"],
      [/restaurant|dining|food/i, "🍽️"],
      [/rent|home living|housing|storage/i, "🏠"],
      [/health|medical|dental/i, "🩺"],
      [/auto|vehicle|transport/i, "🚗"],
      [/cellphone|mobile|phone/i, "📱"],
      [/internet|broadband/i, "🌐"],
      [/software|digital/i, "💻"],
      [/professional|bookkeep|accounting/i, "🧾"],
      [/pml|investment|portfolio/i, "📈"],
      [/line of credit|\bloc\b|loan|debt|interest/i, "🏦"],
      [/contribution/i, "💰"],
      [/transfer/i, "🔄"],
      [/income|deposit|payroll/i, "💵"],
      [/exclude/i, "🚫"],
      [/office|business/i, "💼"],
      [/utility|electric|water|gas/i, "💡"],
      [/travel|flight|hotel/i, "✈️"],
      [/entertainment|activity|event/i, "🎟️"],
      [/gift|donation/i, "🎁"],
      [/subscription/i, "🔁"],
      [/fuel/i, "⛽"],
      [/education|school/i, "🎓"],
      [/pet/i, "🐾"],
      [/child|kid/i, "🧸"],
      [/insurance/i, "🛡️"],
      [/fee|tax/i, "🧾"],
    ];
    return rules.find(([pattern]) => pattern.test(label || ""))?.[1] || "🏷️";
  }

  filterUrl(key, value) {
    const filters = this.filtersFromForm();
    filters[key] = value == null ? [] : [String(value)];
    return `${window.location.pathname}${explorerSearchFromFilters(filters)}`;
  }

  updateFilterAvailability(availability) {
    const availableByKey = {
      detail_category_ids: new Set(availability.detail_category_ids),
      wdg_rollup_ids: new Set(availability.wdg_rollup_ids),
      include_tag_ids: new Set(availability.tag_ids),
      exclude_tag_ids: new Set(availability.tag_ids),
    };

    Object.entries(availableByKey).forEach(([key, available]) => {
      this.formTarget
        .querySelectorAll(`input[name="${key}[]"]:not([value="__none__"])`)
        .forEach((input) => {
          const emphasized =
            available.has(String(input.value)) || input.checked;
          const pill = input.nextElementSibling;
          pill?.setAttribute(
            "data-filter-available",
            String(available.has(String(input.value))),
          );
          pill?.classList.toggle("opacity-40", !emphasized);
          pill?.classList.toggle("saturate-50", !emphasized);
        });
    });

    this.formTarget
      .querySelectorAll("fieldset[data-category-catalog]")
      .forEach((fieldset) => {
        const inputs = [
          ...fieldset.querySelectorAll(
            'input[name="detail_category_ids[]"]:not([value="__none__"])',
          ),
        ];
        fieldset.hidden = !inputs.some(
          (input) =>
            input.checked ||
            availableByKey.detail_category_ids.has(String(input.value)),
        );
      });
  }

  updateExclusionBanner() {
    const filters = this.filtersFromForm();
    const selected = new Set(filters.exclude_tag_ids || []);
    const names = this.tagCatalog
      .filter((tag) => selected.has(String(tag.id)))
      .map(({ name }) => name);
    this.exclusionBannerTarget.hidden = names.length === 0;
    this.exclusionBannerTarget.textContent =
      this.excludedTagsTemplateValue.replace(
        "__TAGS__",
        this.listFormatter.format(names),
      );
  }

  initialFilters() {
    if (hasExplorerFilterSearch(window.location.search)) {
      return explorerFiltersFromSearch(window.location.search);
    }

    try {
      const persisted = localStorage.getItem(this.filterStorageKeyValue);
      if (persisted) {
        this.restoredPersistedFilters = true;
        return explorerPersistableFilters(explorerFiltersFromSearch(persisted));
      }
    } catch (_error) {
      // The server defaults remain available when browser storage is blocked.
    }

    return this.defaultFilters;
  }

  restoreHistoryState() {
    const filters = hasExplorerFilterSearch(window.location.search)
      ? explorerFiltersFromSearch(window.location.search)
      : this.defaultFilters;
    this.implicitAllDetailCategories = !Object.hasOwn(
      filters,
      "detail_category_ids",
    );
    this.syncForm(filters, { clearMissing: true });
    this.applyCurrentFilters({ historyAction: null });
  }

  filtersFromForm() {
    const filters = explorerFiltersFromFormData(new FormData(this.formTarget));
    if (this.implicitAllDetailCategories) {
      const { detail_category_ids: _ignored, ...withoutDetailCategories } =
        filters;
      return withoutDetailCategories;
    }
    return filters;
  }

  syncForm(filters, { clearMissing = false } = {}) {
    const arrayKeys = [
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
    const optionalKeys = new Set([
      "wdg_rollup_ids",
      "include_tag_ids",
      "exclude_tag_ids",
    ]);
    arrayKeys.forEach((key) => {
      const hasFilter = Object.hasOwn(filters, key);
      if (!hasFilter && !clearMissing) return;

      this.formTarget
        .querySelectorAll(`input[data-explorer-dynamic-filter="${key}"]`)
        .forEach((input) => input.remove());
      const inputs = [
        ...this.formTarget.querySelectorAll(
          `input[name="${key}[]"]:not([value="__none__"]):not([data-explorer-dynamic-filter])`,
        ),
      ];
      if (!hasFilter) {
        if (clearMissing) {
          inputs.forEach((input) => {
            input.checked = !optionalKeys.has(key);
          });
        }
        return;
      }

      const selected = new Set((filters[key] || []).map(String));
      const available = new Set(inputs.map(({ value }) => String(value)));
      inputs.forEach((input) => {
        input.checked = selected.has(String(input.value));
      });
      [...selected]
        .filter((value) => !available.has(value))
        .forEach((value) => {
          const input = document.createElement("input");
          input.type = "hidden";
          input.name = `${key}[]`;
          input.value = value;
          input.dataset.explorerDynamicFilter = key;
          this.formTarget.appendChild(input);
        });
    });

    if (Object.hasOwn(filters, "search")) {
      const search = this.formTarget.querySelector('input[name="search"]');
      if (search) search.value = filters.search || "";
    }
  }

  setFilterSelection(key, values) {
    this.syncForm({ [key]: values });
  }

  persistFilters(filters) {
    try {
      localStorage.setItem(
        this.filterStorageKeyValue,
        explorerSearchFromFilters(explorerPersistableFilters(filters)),
      );
    } catch (_error) {
      // Filtering remains in memory when browser storage is blocked.
    }
  }

  clearPersistedFilters() {
    try {
      localStorage.removeItem(this.filterStorageKeyValue);
    } catch (_error) {
      // Reset still updates the in-memory report.
    }
  }

  updateHistory(filters, action) {
    if (!action) return;
    const url = `${window.location.pathname}${explorerSearchFromFilters(filters)}`;
    if (url === `${window.location.pathname}${window.location.search}`) return;

    window.history[`${action}State`](window.history.state, "", url);
  }

  sortChanged() {
    const [field, dir] = this.sortTarget.value.split(/-(?=[^-]+$)/);
    this.table.setSort(field, dir);
  }

  toggleLayout() {
    this.layoutMenuTarget.hidden = !this.layoutMenuTarget.hidden;
  }

  renderLayoutMenu() {
    this.layoutMenuTarget.replaceChildren();
    this.table
      .getColumns()
      .filter((column) => column.getField())
      .forEach((column) => {
        const label = document.createElement("label");
        label.className =
          "flex items-center gap-2 px-2 py-1 text-xs text-primary";
        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = column.isVisible();
        checkbox.addEventListener("change", () => {
          checkbox.checked ? column.show() : column.hide();
          this.persistViewState();
        });
        label.append(
          checkbox,
          document.createTextNode(column.getDefinition().title),
        );
        this.layoutMenuTarget.appendChild(label);
      });
  }

  fitColumns() {
    this.viewState = { ...this.viewState, layout: "fitColumns" };
    this.element.dataset.layoutMode = "fitColumns";
    this.table.setOptions({ layout: "fitColumns" });
    this.persistViewState();
  }

  toggleRollups() {
    const opening = this.rollupPaneTarget.hidden;
    this.rollupPaneTarget.hidden = !opening;
    this.rollupButtonTarget.setAttribute("aria-expanded", String(opening));
    this.viewState = { ...this.viewState, rollupsOpen: opening };
    this.persistViewState();
    requestAnimationFrame(() => this.table.redraw(true));
  }

  restoreRollups() {
    this.rollupPaneTarget.hidden = !this.viewState.rollupsOpen;
    this.rollupButtonTarget.setAttribute(
      "aria-expanded",
      String(this.viewState.rollupsOpen),
    );
  }

  restoreColumnState() {
    const tableColumns = this.table
      .getColumns()
      .filter((column) => column.getField());
    if (tableColumns.length === 0) return false;
    if (!this.viewState.columns) return true;

    const columnsByField = new Map(
      tableColumns.map((column) => [column.getField(), column]),
    );

    let previousField = null;
    this.viewState.columns.forEach(({ field, width, visible }) => {
      const column = columnsByField.get(field);
      if (!column) return;

      if (previousField) {
        this.table.moveColumn(field, previousField, true);
      } else {
        const firstField = tableColumns[0]?.getField();
        if (firstField && firstField !== field) {
          this.table.moveColumn(field, firstField, false);
        }
      }

      column.setWidth(width);
      visible ? column.show() : column.hide();
      previousField = field;
    });

    return true;
  }

  async restoreTableState() {
    if (this.tableStateRestored || !this.restoreColumnState()) {
      return;
    }

    this.tableStateRestored = true;
    this.renderLayoutMenu();
    if (this.currentReport) this.renderReport(this.currentReport);
    this.resolveTableReady?.();
    this.resolveTableReady = null;
  }

  persistViewState() {
    if (!this.table) return;

    const columns = this.table
      .getColumns()
      .filter((column) => column.getField())
      .map((column) => ({
        field: column.getField(),
        width: column.getWidth(),
        visible: column.isVisible(),
      }));
    this.viewState = { ...this.viewState, columns };

    try {
      localStorage.setItem(
        TRANSACTION_EXPLORER_VIEW_STATE_KEY,
        serializeExplorerViewState(this.viewState),
      );
    } catch (_error) {
      // The grid remains usable when browser storage is unavailable.
    }
  }

  loadViewState() {
    try {
      return parseExplorerViewState(
        localStorage.getItem(TRANSACTION_EXPLORER_VIEW_STATE_KEY),
      );
    } catch (_error) {
      return parseExplorerViewState(null);
    }
  }

  collapseAll() {
    this.table.getGroups().forEach((group) => group.hide());
  }

  undo() {
    this.table.undo();
  }

  redo() {
    this.table.redo();
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content;
  }
}
