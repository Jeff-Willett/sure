import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-open"
// Auto-opens a <details> element based on URL param
// Use data-auto-open-param-value="paramName" to open when ?paramName=1 is in URL
export default class extends Controller {
  static values = { param: String, storageKey: String };

  connect() {
    this.restoreStoredState();

    if (!this.hasParamValue || !this.paramValue) return;

    const params = new URLSearchParams(window.location.search);
    if (params.get(this.paramValue) === "1") {
      this.element.open = true;

      // Clean up the URL param after opening
      params.delete(this.paramValue);
      const newUrl = params.toString()
        ? `${window.location.pathname}?${params.toString()}${window.location.hash}`
        : `${window.location.pathname}${window.location.hash}`;
      window.history.replaceState({}, "", newUrl);

      // Scroll into view after opening
      requestAnimationFrame(() => {
        this.element.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }
  }

  remember() {
    if (!this.hasStorageKeyValue) return;

    try {
      localStorage.setItem(this.storageKeyValue, String(this.element.open));
    } catch (_error) {
      // The disclosure still works when browser storage is unavailable.
    }
  }

  restoreStoredState() {
    if (!this.hasStorageKeyValue) return;

    try {
      const savedState = localStorage.getItem(this.storageKeyValue);
      if (savedState !== null) this.element.open = savedState === "true";
    } catch (_error) {
      // The disclosure still works when browser storage is unavailable.
    }
  }
}
