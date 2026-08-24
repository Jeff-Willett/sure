import { Controller } from "@hotwired/stimulus";

import {
  focusFallback,
  nextEditableCell,
  shouldOpenEditor,
} from "utils/transaction_explorer_grid_state";
import { captureEditResult } from "utils/transaction_explorer_undo";

export default class extends Controller {
  #onBeforeRender;
  #onBeforeStreamRender;
  #onClick;
  #onDocumentClick;
  #onDoubleClick;
  #onFocusIn;
  #onFocusOut;
  #onKeydown;
  #onRender;

  static targets = ["announcement", "cell", "editToggle", "scroll"];

  static values = {
    editMode: { type: Boolean, default: false },
  };

  connect() {
    this.active = null;
    this.stateBeforeRender = null;
    this.undoNotices = new Map();
    this.#onClick = (event) => this.selectCell(event);
    this.#onDocumentClick = (event) => this.handleDocumentClick(event);
    this.#onDoubleClick = (event) => this.openFromPointer(event);
    this.#onKeydown = (event) => this.handleKeydown(event);
    this.#onFocusIn = (event) => this.handleFocusIn(event);
    this.#onFocusOut = (event) => this.handleFocusOut(event);
    this.#onBeforeRender = () => this.captureRenderState();
    this.#onRender = () =>
      requestAnimationFrame(() => this.restoreRenderState());
    this.#onBeforeStreamRender = (event) =>
      this.handleBeforeStreamRender(event);

    this.element.addEventListener("click", this.#onClick);
    this.element.addEventListener("dblclick", this.#onDoubleClick);
    this.element.addEventListener("keydown", this.#onKeydown);
    this.element.addEventListener("focusin", this.#onFocusIn);
    this.element.addEventListener("focusout", this.#onFocusOut);
    document.addEventListener("click", this.#onDocumentClick);
    document.addEventListener("turbo:before-render", this.#onBeforeRender);
    document.addEventListener("turbo:render", this.#onRender);
    document.addEventListener(
      "turbo:before-stream-render",
      this.#onBeforeStreamRender,
    );

    this.#syncEditMode();
  }

  disconnect() {
    this.element.removeEventListener("click", this.#onClick);
    this.element.removeEventListener("dblclick", this.#onDoubleClick);
    this.element.removeEventListener("keydown", this.#onKeydown);
    this.element.removeEventListener("focusin", this.#onFocusIn);
    this.element.removeEventListener("focusout", this.#onFocusOut);
    document.removeEventListener("click", this.#onDocumentClick);
    this.undoNotices.clear();
    document.removeEventListener("turbo:before-render", this.#onBeforeRender);
    document.removeEventListener("turbo:render", this.#onRender);
    document.removeEventListener(
      "turbo:before-stream-render",
      this.#onBeforeStreamRender,
    );
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
    const cells = this.#cellIdentities();
    const openCell = this.cellTargets.find(
      (cell) => this.#editorFor(cell)?.hidden === false,
    );

    this.stateBeforeRender = {
      active: activeCell ? this.#identityForCell(activeCell) : this.active,
      activeIndex: activeCell
        ? cells.findIndex(
            (cell) =>
              cell.entryId === activeCell.dataset.entryId &&
              cell.scheme === activeCell.dataset.scheme,
          )
        : -1,
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
    const exactIdentity = preferred && this.#findIdentity(preferred);
    let identity = exactIdentity;
    const movedOutOfFilter = Boolean(preferred && !exactIdentity);

    if (movedOutOfFilter) {
      identity = focusFallback({
        cells: this.#cellIdentities(),
        previous: {
          ...preferred,
          index: state.activeIndex,
        },
      });
    }

    if (movedOutOfFilter) {
      this.#announce(
        this.#translation(
          "row_moved_out_of_filter",
          "This transaction moved out of the current filter.",
        ),
      );
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

  handleBeforeStreamRender(event) {
    const target = event.target?.getAttribute("target");
    if (target === "transaction-explorer-ledger") {
      this.captureRenderState();
      return;
    }

    if (target !== "transaction-explorer-edit-result") return;

    const render = event.detail?.render;
    if (typeof render !== "function") return;

    event.detail.render = (streamElement) => {
      const capturedResult = captureEditResult(streamElement);
      const result = render(streamElement);
      Promise.resolve(result).finally(() =>
        requestAnimationFrame(() => {
          this.queueUndoNotice(capturedResult);
          this.restoreRenderState();
        }),
      );
      return result;
    };
  }

  handleDocumentClick(event) {
    const undoButton = event.target.closest(
      "[data-transaction-explorer-grid-undo]",
    );
    if (!undoButton) return;

    const notice = undoButton.closest(
      "[data-transaction-explorer-undo-notice]",
    );
    const changeId = notice?.dataset.changeId;
    if (!notice || !changeId || !this.undoNotices.has(changeId)) return;

    event.preventDefault();
    this.submitUndo(changeId, notice, undoButton);
  }

  queueUndoNotice(result = null) {
    const capturedResult =
      result ||
      document.querySelector(
        "#transaction-explorer-edit-result [data-change-id]",
      );
    if (!capturedResult) return;

    const changeId = capturedResult.dataset.changeId;
    if (!changeId || this.undoNotices.has(changeId)) return;

    const template = capturedResult.querySelector(
      "template[data-transaction-explorer-undo-template]",
    );
    const tray = document.querySelector("#notification-tray");
    if (!template || !tray) return;

    const fragment = template.content.cloneNode(true);
    const notice = fragment.firstElementChild;
    if (!notice) return;

    notice.dataset.changeId = changeId;
    notice.dataset.revertUrl = capturedResult.dataset.revertUrl;
    notice.dataset.historyUrl = capturedResult.dataset.historyUrl;
    notice.dataset.categoryLabel = capturedResult.dataset.categoryLabel;
    notice.dataset.conflictTemplate = capturedResult.dataset.conflictTemplate;
    tray.append(notice);
    this.undoNotices.set(changeId, notice);

    window.setTimeout(() => {
      if (this.undoNotices.get(changeId) !== notice) return;

      this.undoNotices.delete(changeId);
      notice.remove();
    }, 10000);
  }

  async submitUndo(changeId, notice, undoButton) {
    if (notice.dataset.pending === "true") return;

    notice.dataset.pending = "true";
    undoButton.disabled = true;
    undoButton.setAttribute("aria-busy", "true");

    try {
      const response = await fetch(notice.dataset.revertUrl, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
        credentials: "same-origin",
      });

      if (response.ok) {
        this.undoNotices.delete(changeId);
        notice.remove();
        Turbo.visit(window.location.href, { action: "replace" });
        return;
      }

      if (response.status === 409) {
        const payload = await response.json();
        this.showUndoConflict(notice, payload);
        this.undoNotices.delete(changeId);
        return;
      }

      throw new Error(`Undo failed with status ${response.status}`);
    } catch (_error) {
      delete notice.dataset.pending;
      undoButton.disabled = false;
      undoButton.removeAttribute("aria-busy");
    }
  }

  showUndoConflict(notice, payload) {
    const message = notice.querySelector(
      "[data-transaction-explorer-undo-message]",
    );
    const undoButton = notice.querySelector(
      "[data-transaction-explorer-grid-undo]",
    );
    const historyLink = notice.querySelector(
      "[data-transaction-explorer-grid-history]",
    );

    if (message) {
      message.textContent = (notice.dataset.conflictTemplate || "").replace(
        "__CATEGORY__",
        payload.current_category,
      );
    }
    if (undoButton) undoButton.remove();
    if (historyLink) {
      historyLink.href = payload.history_url || notice.dataset.historyUrl;
      historyLink.classList.remove("hidden");
    }
    delete notice.dataset.pending;
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
