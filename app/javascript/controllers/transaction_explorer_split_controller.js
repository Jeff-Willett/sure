import { Controller } from "@hotwired/stimulus";
import { clampSidebarWidth } from "utils/sidebar_resize";

const STORAGE_KEY = "sure.transactionExplorer.rollupWidth";
const MIN_ROLLUP_WIDTH = 260;
const MIN_LEDGER_WIDTH = 480;
const MAX_ROLLUP_WIDTH = 520;
const HANDLE_WIDTH = 8;
const DEFAULT_RATIO = 0.32;
const KEY_STEP = 16;

export default class extends Controller {
  static targets = ["handle"];

  #dragging = false;
  #onMove = null;
  #onUp = null;
  #resizeObserver = null;

  connect() {
    this.#setWidth(this.#storedWidth() ?? this.#defaultWidth());

    if (typeof ResizeObserver !== "undefined") {
      this.#resizeObserver = new ResizeObserver(() => {
        this.#setWidth(this.#currentWidth());
      });
      this.#resizeObserver.observe(this.element);
    }
  }

  disconnect() {
    this.#teardownDrag();
    this.#resizeObserver?.disconnect();
  }

  start(event) {
    event.preventDefault();
    this.#dragging = true;
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";

    this.#onMove = (moveEvent) => this.#resize(moveEvent.clientX);
    this.#onUp = () => this.#finish();
    window.addEventListener("pointermove", this.#onMove);
    window.addEventListener("pointerup", this.#onUp, { once: true });
  }

  keydown(event) {
    let width;
    if (event.key === "ArrowLeft") {
      width = this.#currentWidth() - KEY_STEP;
    } else if (event.key === "ArrowRight") {
      width = this.#currentWidth() + KEY_STEP;
    } else if (event.key === "Home") {
      width = this.#defaultWidth();
    } else {
      return;
    }

    event.preventDefault();
    this.#commit(width);
  }

  reset() {
    this.#commit(this.#defaultWidth());
  }

  #resize(clientX) {
    if (!this.#dragging) return;

    const bounds = this.element.getBoundingClientRect();
    this.#setWidth(clientX - bounds.left);
  }

  #finish() {
    if (!this.#dragging) return;

    this.#persist(this.#currentWidth());
    this.#teardownDrag();
  }

  #commit(width) {
    this.#setWidth(width);
    this.#persist(this.#currentWidth());
  }

  #setWidth(rawWidth) {
    const width = this.#clamp(rawWidth);
    this.element.style.setProperty(
      "--transaction-explorer-rollup-width",
      `${width}px`,
    );
    this.handleTarget.setAttribute("aria-valuemin", String(MIN_ROLLUP_WIDTH));
    this.handleTarget.setAttribute(
      "aria-valuemax",
      String(this.#clamp(Number.POSITIVE_INFINITY)),
    );
    this.handleTarget.setAttribute("aria-valuenow", String(width));
  }

  #clamp(rawWidth) {
    return clampSidebarWidth(rawWidth, {
      viewportWidth: this.element.getBoundingClientRect().width,
      navbarWidth: 0,
      otherWidth: HANDLE_WIDTH,
      min: MIN_ROLLUP_WIDTH,
      minMain: MIN_LEDGER_WIDTH,
      absMax: MAX_ROLLUP_WIDTH,
    });
  }

  #defaultWidth() {
    return this.element.getBoundingClientRect().width * DEFAULT_RATIO;
  }

  #currentWidth() {
    const width = Number.parseInt(
      this.element.style.getPropertyValue(
        "--transaction-explorer-rollup-width",
      ),
      10,
    );
    return Number.isFinite(width) ? width : this.#defaultWidth();
  }

  #storedWidth() {
    try {
      const width = Number.parseInt(localStorage.getItem(STORAGE_KEY), 10);
      return Number.isFinite(width) ? width : null;
    } catch (_error) {
      return null;
    }
  }

  #persist(width) {
    try {
      localStorage.setItem(STORAGE_KEY, String(width));
    } catch (_error) {
      // A blocked local store should not prevent resizing.
    }
  }

  #teardownDrag() {
    if (this.#onMove) window.removeEventListener("pointermove", this.#onMove);
    if (this.#onUp) window.removeEventListener("pointerup", this.#onUp);
    document.body.style.cursor = "";
    document.body.style.userSelect = "";
    this.#onMove = null;
    this.#onUp = null;
    this.#dragging = false;
  }
}
