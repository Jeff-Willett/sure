export function captureEditResult(streamElement) {
  const result = streamElement
    ?.querySelector?.("template")
    ?.content?.querySelector?.("[data-change-id]");

  return result?.cloneNode?.(true) || null;
}
