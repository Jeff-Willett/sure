import { Controller } from "@hotwired/stimulus";
import { TabulatorFull as Tabulator } from "tabulator-tables";

export default class extends Controller {
  static targets = ["data", "grid", "layoutMenu", "sort"];
  static values = { persistenceId: String };

  connect() {
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
        sorter: "date",
      },
      { title: "Entity", field: "entity", frozen: true, width: 76 },
      { title: "WDG rollup", field: "wdg_rollup", width: 190 },
      { title: "Detail category", field: "detail_category", width: 180 },
      { title: "Tags", field: "tags", width: 220 },
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
}
