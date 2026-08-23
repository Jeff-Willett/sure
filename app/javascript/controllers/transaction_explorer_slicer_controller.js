import { Controller } from "@hotwired/stimulus";
import {
  checkedStateForMode,
  uniformCheckedState,
} from "utils/slicer_selection";

export default class extends Controller {
  static targets = ["checkbox", "singleIcon", "multipleIcon", "modeButton"];
  static values = {
    key: String,
    singleLabel: String,
    multipleLabel: String,
  };

  connect() {
    this.multiple = this.#storedMode() !== "single";
    this.#renderMode();
  }

  selectionChanged(event) {
    const changedIndex = this.checkboxTargets.indexOf(event.target);
    const nextState = checkedStateForMode({
      current: this.checkboxTargets.map((checkbox) => checkbox.checked),
      changedIndex,
      checked: event.target.checked,
      multiple: this.multiple,
    });

    this.#applyState(nextState);
  }

  selectAll() {
    this.#applyState(uniformCheckedState(this.checkboxTargets.length, true));
    this.#submit();
  }

  clearAll() {
    this.#applyState(uniformCheckedState(this.checkboxTargets.length, false));
    this.#submit();
  }

  toggleMode() {
    this.multiple = !this.multiple;
    this.#storeMode();
    this.#renderMode();
  }

  #applyState(nextState) {
    this.checkboxTargets.forEach((checkbox, index) => {
      checkbox.checked = nextState[index];
    });
  }

  #renderMode() {
    this.multipleIconTarget.classList.toggle("hidden", !this.multiple);
    this.singleIconTarget.classList.toggle("hidden", this.multiple);
    this.modeButtonTarget.setAttribute("aria-pressed", String(!this.multiple));
    const label = this.multiple
      ? this.singleLabelValue
      : this.multipleLabelValue;
    this.modeButtonTarget.setAttribute("aria-label", label);
    this.modeButtonTarget.setAttribute("title", label);
  }

  #submit() {
    this.element.form?.requestSubmit();
  }

  #storedMode() {
    try {
      return sessionStorage.getItem(this.#storageKey());
    } catch (_error) {
      return null;
    }
  }

  #storeMode() {
    try {
      sessionStorage.setItem(
        this.#storageKey(),
        this.multiple ? "multiple" : "single",
      );
    } catch (_error) {
      // A blocked session store should not prevent slicer use.
    }
  }

  #storageKey() {
    return `transaction-explorer-slicer:${this.keyValue}`;
  }
}
