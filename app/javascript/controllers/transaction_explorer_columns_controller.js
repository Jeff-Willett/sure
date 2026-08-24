import { Controller } from "@hotwired/stimulus";

import {
  TRANSACTION_EXPLORER_COLUMNS,
  TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY,
  clampWidth,
  deriveDesktopStickyOffsets,
  parseStoredWidths,
  resetWidth,
  resizeWidths,
} from "utils/transaction_explorer_column_widths";

const KEY_STEP = 16;

export default class extends Controller {
  static targets = ["colgroup", "handle"];

  connect() {
    this.widths = this.#readStoredWidths();
    this.#applyWidths();
    this.#drag = null;
    this.#onPointerMove = (event) => this.#resizeFromPointer(event);
    this.#onPointerUp = () => this.#endResize();
  }

  disconnect() {
    this.#endResize();
  }

  colgroupTargetConnected() {
    this.#applyWidths();
  }

  start(event) {
    if (event.button !== 0) return;

    event.preventDefault();
    const column = event.currentTarget.dataset.column;
    if (!column || !TRANSACTION_EXPLORER_COLUMNS[column]) return;

    this.#drag = {
      column,
      startX: event.clientX,
      startWidth: this.widths[column],
    };
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";
    window.addEventListener("pointermove", this.#onPointerMove);
    window.addEventListener("pointerup", this.#onPointerUp, { once: true });
  }

  keydown(event) {
    const column = event.currentTarget.dataset.column;
    if (!column || !TRANSACTION_EXPLORER_COLUMNS[column]) return;

    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      event.preventDefault();
      const delta = event.key === "ArrowRight" ? KEY_STEP : -KEY_STEP;
      this.widths = resizeWidths(this.widths, column, delta);
      this.#persistAndApply();
    } else if (event.key === "Home") {
      event.preventDefault();
      this.widths = { ...this.widths, [column]: resetWidth(column) };
      this.#persistAndApply();
    }
  }

  resetColumn(event) {
    const column = event.currentTarget.dataset.column;
    if (!column || !TRANSACTION_EXPLORER_COLUMNS[column]) return;

    this.widths = { ...this.widths, [column]: resetWidth(column) };
    this.#persistAndApply();
  }

  reset() {
    try {
      localStorage.removeItem(TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY);
    } catch (_error) {
      // Widths still reset for the current page when storage is unavailable.
    }

    this.widths = parseStoredWidths(null);
    this.#applyWidths();
  }

  #resizeFromPointer(event) {
    if (!this.#drag) return;

    const { column, startX, startWidth } = this.#drag;
    this.widths = {
      ...this.widths,
      [column]: clampWidth(column, startWidth + event.clientX - startX),
    };
    this.#applyWidths();
  }

  #endResize() {
    if (!this.#drag) return;

    this.#persist();
    this.#drag = null;
    document.body.style.userSelect = "";
    document.body.style.cursor = "";
    window.removeEventListener("pointermove", this.#onPointerMove);
    window.removeEventListener("pointerup", this.#onPointerUp);
  }

  #readStoredWidths() {
    try {
      return parseStoredWidths(
        localStorage.getItem(TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY),
      );
    } catch (_error) {
      return parseStoredWidths(null);
    }
  }

  #persistAndApply() {
    this.#persist();
    this.#applyWidths();
  }

  #persist() {
    try {
      localStorage.setItem(
        TRANSACTION_EXPLORER_COLUMN_WIDTHS_KEY,
        JSON.stringify(this.widths),
      );
    } catch (_error) {
      // Presentation state remains applied for this session.
    }
  }

  #applyWidths() {
    if (this.hasColgroupTarget) {
      this.colgroupTarget
        .querySelectorAll("col[data-column]")
        .forEach((col) => {
          const column = col.dataset.column;
          if (this.widths[column] == null) return;
          col.style.width = `${this.widths[column]}px`;
        });
    }

    const offsets = deriveDesktopStickyOffsets(this.widths);
    this.element.style.setProperty(
      "--transaction-explorer-date-offset",
      `${offsets.date}px`,
    );
    this.element.style.setProperty(
      "--transaction-explorer-entity-offset",
      `${offsets.entity}px`,
    );
  }
}
