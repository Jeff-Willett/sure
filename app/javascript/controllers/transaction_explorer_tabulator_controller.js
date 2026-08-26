import { Controller } from "@hotwired/stimulus";
import { TabulatorFull as Tabulator } from "tabulator-tables";
import { parseTagNames } from "utils/tag_input";

export default class extends Controller {
  static targets = [
    "categoryData",
    "data",
    "grid",
    "layoutMenu",
    "sort",
    "tagData",
  ];
  static values = { createTagUrl: String, persistenceId: String };

  connect() {
    this.categoryOptions = JSON.parse(
      this.categoryDataTarget.content.textContent,
    );
    this.tagCatalog = JSON.parse(this.tagDataTarget.content.textContent);
    this.table = new Tabulator(this.gridTarget, {
      data: JSON.parse(
        this.dataTarget.content?.textContent || this.dataTarget.textContent,
      ),
      index: "id",
      layout: "fitDataStretch",
      height: "100%",
      movableColumns: true,
      selectableRows: true,
      selectableRowsRangeMode: "drag",
      clipboard: true,
      clipboardCopyRowRange: "selected",
      history: true,
      groupBy: "entity",
      groupStartOpen: true,
      persistence: { columns: true, sort: true, group: true },
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

    this.table.on("tableBuilt", () => this.renderLayoutMenu());
  }

  disconnect() {
    this.table?.destroy();
    this.table = null;
  }

  get columns() {
    return [
      { title: "Status", field: "workflow_status", frozen: true, width: 118 },
      {
        title: "Open",
        field: "open_url",
        frozen: true,
        width: 62,
        formatter: this.openFormatter,
        headerSort: false,
        clipboard: false,
      },
      { title: "Type", field: "type", frozen: true, width: 90 },
      {
        title: "Date",
        field: "date",
        frozen: true,
        width: 105,
        sorter: "string",
      },
      { title: "Entity", field: "entity", frozen: true, width: 76 },
      { title: "WDG rollup", field: "wdg_rollup", width: 190 },
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

  openFormatter(cell) {
    const link = document.createElement("a");
    link.href = cell.getValue();
    link.textContent = "Open";
    link.className = "text-link hover:underline";
    link.dataset.turboFrame = "drawer";
    return link;
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
        Accept: "text/vnd.turbo-stream.html",
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

    const label =
      this.categoryValues(data.detail_scheme)[nextId] || "Uncategorized";
    row.update({ detail_category: label });
  }

  async saveTags(cell) {
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

    const normalized = parseTagNames(cell.getValue()).join(", ");
    row.update({ tags: normalized });
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
        checkbox.addEventListener("change", () =>
          checkbox.checked ? column.show() : column.hide(),
        );
        label.append(
          checkbox,
          document.createTextNode(column.getDefinition().title),
        );
        this.layoutMenuTarget.appendChild(label);
      });
  }

  fitColumns() {
    this.table.setOptions({ layout: "fitColumns" });
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
