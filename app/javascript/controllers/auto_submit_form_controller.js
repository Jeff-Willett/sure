import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  // By default, auto-submit is "opt-in" to avoid unexpected behavior.  Each `auto` target
  // will trigger a form submission when the configured event is triggered.
  static targets = ["auto"];
  static values = {
    triggerEvent: { type: String, default: "input" },
    persistenceKey: String,
  };

  connect() {
    if (this.#hasFilterQuery()) {
      this.rememberFilters();
    } else {
      this.restoreRememberedFilters();
    }

    this.autoTargets.forEach((element) => {
      const event = this.#getTriggerEvent(element);
      element.addEventListener(event, this.handleInput);
    });
    this.element.addEventListener("submit", this.rememberFilters);
  }

  disconnect() {
    this.autoTargets.forEach((element) => {
      const event = this.#getTriggerEvent(element);
      element.removeEventListener(event, this.handleInput);
    });
    this.element.removeEventListener("submit", this.rememberFilters);
  }

  handleInput = (event) => {
    const target = event.target;

    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      this.element.requestSubmit();
    }, this.#debounceTimeout(target));
  };

  rememberFilters = () => {
    if (!this.hasPersistenceKeyValue) return;

    try {
      const query = new URLSearchParams(new FormData(this.element)).toString();
      localStorage.setItem(this.persistenceKeyValue, query);
    } catch (_error) {
      // Filtering still works when browser storage is unavailable.
    }
  };

  clearRememberedFilters() {
    if (!this.hasPersistenceKeyValue) return;

    try {
      localStorage.removeItem(this.persistenceKeyValue);
    } catch (_error) {
      // Reset navigation still works when browser storage is unavailable.
    }
  }

  restoreRememberedFilters() {
    if (!this.hasPersistenceKeyValue || this.#hasFilterQuery()) return;

    try {
      const query = localStorage.getItem(this.persistenceKeyValue);
      if (!query) return;

      const url = `${window.location.pathname}?${query}`;
      window.Turbo?.visit(url, { action: "replace" });
    } catch (_error) {
      // The server-rendered default remains available without browser storage.
    }
  }

  #hasFilterQuery() {
    const filterNames = [
      "entity_ids[]",
      "years[]",
      "months[]",
      "types[]",
      "detail_category_ids[]",
      "wdg_rollup_ids[]",
      "include_tag_ids[]",
      "exclude_tag_ids[]",
      "search",
    ];
    const params = new URLSearchParams(window.location.search);
    return filterNames.some((name) => params.has(name));
  }

  #getTriggerEvent(element) {
    // Check if element has explicit trigger event set
    if (element.dataset.autosubmitTriggerEvent) {
      return element.dataset.autosubmitTriggerEvent;
    }

    // Check if form has explicit trigger event set
    if (this.triggerEventValue !== "input") {
      return this.triggerEventValue;
    }

    // Otherwise, choose trigger event based on element type
    const type = element.type || element.tagName;

    switch (type.toLowerCase()) {
      case "text":
      case "email":
      case "password":
      case "search":
      case "tel":
      case "url":
      case "textarea":
        return "blur";
      case "number":
      case "date":
      case "datetime-local":
      case "month":
      case "time":
      case "week":
      case "color":
        return "change";
      case "checkbox":
      case "radio":
      case "select":
      case "select-one":
      case "select-multiple":
        return "change";
      case "range":
        return "input";
      default:
        return "blur";
    }
  }

  #debounceTimeout(element) {
    if (element.dataset.autosubmitDebounceTimeout) {
      return Number.parseInt(element.dataset.autosubmitDebounceTimeout);
    }

    const type = element.type || element.tagName;

    switch (type.toLowerCase()) {
      case "input":
      case "textarea":
        return 500;
      case "select-one":
      case "select-multiple":
        return 0;
      default:
        return 500;
    }
  }
}
