export function checkedStateForMode({ current, changedIndex, checked, multiple }) {
  if (!multiple && checked) {
    return current.map((_value, index) => index === changedIndex);
  }

  return current.map((value, index) => (index === changedIndex ? checked : value));
}

export function uniformCheckedState(count, checked) {
  return Array.from({ length: count }, () => checked);
}
