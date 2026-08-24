import { Controller } from "@hotwired/stimulus";

import {
  focusFallback,
  nextEditableCell,
  shouldOpenEditor,
} from "utils/transaction_explorer_grid_state";

export default class extends Controller {
  static targets = ["announcement", "cell", "editToggle", "scroll"];

  static values = {
    editMode: { type: Boolean, default: false },
  };

  connect() {
    this.active = null;
    this.stateBeforeRender = null;
    this.#onClick = (event) => this.selectCell(event);
    this.#onDoubleClick = (event) => this.openFromPointer(event);
    this.#onKeydown = (event) => this.handleKeydown(event);
    this.#onFocusIn = (event) => this.handleFocusIn(event);
    this.#onFocusOut = (event) => this.handleFocusOut(event);
    this.#onBeforeRender = () => this.captureRenderState();
    this.#onRender = () =>
      requestAnimationFrame(() => this.restoreRenderState());

    this.element.addEventListener("click", this.#onClick);
    this.element.addEventListener("dblclick", this.#onDoubleClick);
    this.element.addEventListener("keydown", this.#onKeydown);
    this.element.addEventListener("focusin", this.#onFocusIn);
    this.element.addEventListener("focusout", this.#onFocusOut);
    document.addEventListener("turbo:before-render", this.#onBeforeRender);
    document.addEventListener("turbo:render", this.#onRender);

    this.#syncEditMode();
  }

  disconnect() {
    this.element.removeEventListener("click", this.#onClick);
    this.element.removeEventListener("dblclick", this.#onDoubleClick);
    this.element.removeEventListener("keydown", this.#onKeydown);
    this.element.removeEventListener("focusin", this.#onFocusIn);
    this.element.removeEventListener("focusout", this.#onFocusOut);
    document.removeEventListener("turbo:before-render", this.#onBeforeRender);
    document.removeEventListener("turbo:render", this.#onRender);
  }

  toggleEditMode(event) {
    event?.preventDefault();
    this.editModeValue = !this.editModeValue;
    this.#syncEditMode();
  }

  selectCell(event) {
    const cell = this.#cellForEvent(event);
    if (!cell || !this.editModeValue || event.target.closest("form")) return;

    this.#setActive(cell);
  }

  openFromPointer(event) {
    const cell = this.#cellForEvent(event);
    if (!cell || !this.editModeValue || event.target.closest("form")) return;

    event.preventDefault();
    this.#setActive(cell);
    this.#openEditor(cell);
  }

  handleKeydown(event) {
    const cell = this.#cellForEvent(event);
    if (!cell || !this.editModeValue) return;

    const editor = event.target.closest("[data-editor]");
    if (editor) {
      if (event.key === "Escape") {
        event.preventDefault();
        this.#cancelEditor(cell);
      } else if (event.key === "Enter") {
        event.preventDefault();
        this.#submitCell(cell);
      }
      return;
    }

    const printable = this.#isPrintable(event);
    if (shouldOpenEditor({ key: event.key, printable })) {
      event.preventDefault();
      this.#openEditor(cell, printable ? event.key : null);
      return;
    }

    if (
      !["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Tab"].includes(
        event.key,
      )
    )
      return;

    const next = nextEditableCell({
      cells: this.#cellIdentities(),
      active: this.#identityForCell(cell),
      key: event.key,
      shiftKey: event.shiftKey,
    });
    if (!next) return;

    event.preventDefault();
    this.#focusIdentity(next);
  }

  submitEditor(event) {
    const cell = this.#cellForEvent(event);
    if (!cell) return;

    event.currentTarget.setAttribute("aria-busy", "true");
    cell.dataset.pending = "true";
  }

  submitOnChange(event) {
    const cell = this.#cellForEvent(event);
    if (!cell || cell.dataset.pending === "true") return;

    this.#submitCell(cell);
  }

  captureRenderState() {
    const activeCell = this.#activeCell();
    const openCell = this.cellTargets.find(
      (cell) => this.#editorFor(cell)?.hidden === false,
    );

    this.stateBeforeRender = {
      active: activeCell ? this.#identityForCell(activeCell) : this.active,
      editMode: this.editModeValue,
      open: openCell ? this.#identityForCell(openCell) : null,
      scrollLeft: this.hasScrollTarget ? this.scrollTarget.scrollLeft : 0,
      scrollTop: this.hasScrollTarget ? this.scrollTarget.scrollTop : 0,
    };
  }

  restoreRenderState() {
    const state = this.stateBeforeRender;
    if (!state) return;

    this.editModeValue = state.editMode;
    this.#syncEditMode();

    if (this.hasScrollTarget) {
      this.scrollTarget.scrollLeft = state.scrollLeft;
      this.scrollTarget.scrollTop = state.scrollTop;
    }

    const result = document.querySelector(
      "#transaction-explorer-edit-result [data-entry-id][data-scheme]",
    );
    const preferred = result
      ? { entryId: result.dataset.entryId, scheme: result.dataset.scheme }
      : state.active;
    let identity = preferred && this.#findIdentity(preferred);

    if (!identity && preferred) {
      identity = focusFallback({
        cells: this.#cellIdentities(),
        previous: {
          ...preferred,
          index: this.#cellIdentities().findIndex(
            (cell) => cell.entryId === preferred.entryId,
          ),
        },
      });
      if (identity && preferred.entryId !== identity.entryId) {
        this.#announce(
          this.#translation(
            "row_moved_out_of_filter",
            "This transaction moved out of the current filter.",
          ),
        );
      }
    }

    if (identity) {
      this.#focusIdentity(identity, { preventScroll: true });
      if (
        state.open &&
        identity.entryId === state.open.entryId &&
        identity.scheme === state.open.scheme
      ) {
        this.#openEditor(this.#activeCell());
      }
    }

    this.stateBeforeRender = null;
  }

  handleFocusIn(event) {
    const cell = this.#cellForEvent(event);
    if (cell && this.editModeValue && !event.target.closest("[data-editor]"))
      this.#setActive(cell);
  }

  handleFocusOut(event) {
    const cell = this.#cellForEvent(event);
    if (!cell) return;

    const related = event.relatedTarget;
    if (related && cell.contains(related)) return;
    if (
      this.#editorFor(cell)?.hidden === false &&
      cell.dataset.pending !== "true"
    )
      this.#cancelEditor(cell);
  }

  #syncEditMode() {
    this.element.dataset.transactionExplorerGridEditModeValue = String(
      this.editModeValue,
    );
    this.editToggleTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(this.editModeValue));
    });

    const cells = this.cellTargets;
    cells.forEach((cell) => {
      cell.tabIndex = -1;
      cell.setAttribute("aria-selected", "false");
    });

    if (!this.editModeValue) {
      cells.forEach((cell) => this.#cancelEditor(cell));
      this.active = null;
      return;
    }

    const active = this.#activeCell() || cells[0];
    if (active) this.#setActive(active, { focus: false });
  }

  #setActive(cell, { focus = false, preventScroll = false } = {}) {
    if (!cell) return;

    this.active = this.#identityForCell(cell);
    this.cellTargets.forEach((candidate) => {
      const selected = candidate === cell;
      candidate.tabIndex = selected ? 0 : -1;
      candidate.setAttribute("aria-selected", String(selected));
    });
    if (focus) cell.focus({ preventScroll });
  }

  #openEditor(cell, printable = null) {
    if (!cell || cell.dataset.pending === "true") return;

    this.cellTargets.forEach((candidate) => {
      if (candidate !== cell) this.#cancelEditor(candidate);
    });

    const editor = this.#editorFor(cell);
    const select = editor?.querySelector("select");
    if (!editor || !select) return;

    editor.hidden = false;
    cell.dataset.open = "true";
    this.#setActive(cell);
    if (printable) {
      const option = Array.from(select.options).find((candidate) =>
        candidate.textContent
          .trim()
          .toLocaleLowerCase()
          .startsWith(printable.toLocaleLowerCase()),
      );
      if (option) select.value = option.value;
    }
    select.focus({ preventScroll: true });
  }

  #cancelEditor(cell) {
    const editor = this.#editorFor(cell);
    const select = editor?.querySelector("select");
    if (!editor || !select || cell.dataset.pending === "true") return;

    select.value = cell.dataset.categoryId || "";
    editor.hidden = true;
    delete cell.dataset.open;
  }

  #submitCell(cell) {
    const form = this.#formFor(cell);
    if (!form || cell.dataset.pending === "true") return;

    cell.dataset.pending = "true";
    form.setAttribute("aria-busy", "true");
    form.requestSubmit();
  }

  #focusIdentity(identity, options = {}) {
    const cell = this.cellTargets.find(
      (candidate) =>
        candidate.dataset.entryId === identity.entryId &&
        candidate.dataset.scheme === identity.scheme,
    );
    if (!cell) return;

    this.#setActive(cell, {
      focus: true,
      preventScroll: options.preventScroll,
    });
  }

  #cellForEvent(event) {
    const cell = event.target.closest("[data-entry-id][data-scheme]");
    return cell && this.element.contains(cell) ? cell : null;
  }

  #editorFor(cell) {
    return cell?.querySelector("[data-editor]");
  }

  #formFor(cell) {
    return this.#editorFor(cell)?.querySelector("form");
  }

  #activeCell() {
    return this.cellTargets.find(
      (cell) =>
        cell.dataset.entryId === this.active?.entryId &&
        cell.dataset.scheme === this.active?.scheme,
    );
  }

  #identityForCell(cell) {
    return cell
      ? { entryId: cell.dataset.entryId, scheme: cell.dataset.scheme }
      : null;
  }

  #cellIdentities() {
    return this.cellTargets.map((cell) => this.#identityForCell(cell));
  }

  #findIdentity(identity) {
    return this.#cellIdentities().find(
      (candidate) =>
        candidate.entryId === identity.entryId &&
        candidate.scheme === identity.scheme,
    );
  }

  #isPrintable(event) {
    return (
      event.key.length === 1 &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.altKey
    );
  }

  #announce(message) {
    if (this.hasAnnouncementTarget)
      this.announcementTarget.textContent = message;
  }

  #translation(key, fallback) {
    return (
      document.documentElement.dataset[
        `translationMyfinTransactionExplorer${key}`
      ] || fallback
    );
  }
}
