// The pencil case: small stationery drawings for the toolbar and the note card (ART_STYLE.md). Each
// is a 24×24 SVG. Outlines use currentColor; the ink parts use --ink-color, so a tool shows the
// colour it writes in.

const PATHS = {
  // A highlighter lying diagonally, chisel tip at the bottom left.
  highlighter: `<path d="M13.2 4.3l6.5 6.5-8.6 8.6-6.5-6.5z"/><path d="M11 6.6l6.4 6.4"/><path class="ink" d="M4.6 12.9l6.5 6.5-3.4 1.5-4.6-4.6z"/><path class="ink" d="M2.6 22h6.2" stroke-width="2.4"/>`,
  // A fine pen with a red nib.
  pen: `<path d="M16.6 3.4l4 4-10.8 10.8-4-4z"/><path d="M14.4 5.6l4 4"/><path class="ink" d="M5.8 14.2l4 4-5.6 1.6z"/>`,
  // A pad of sticky notes with the top sheet's corner folded.
  pad: `<path class="ink" d="M4.5 4.5h15v9.8l-5.2 5.2H4.5z"/><path d="M19.5 14.3h-5.2v5.2"/><path d="M8 9h8M8 12h4.5"/>`,
  copy: `<rect x="8.5" y="8.5" width="11" height="11" rx="2.2"/><path d="M15.5 8.5V6.2a1.7 1.7 0 0 0-1.7-1.7H6.2a1.7 1.7 0 0 0-1.7 1.7v7.6a1.7 1.7 0 0 0 1.7 1.7h2.3"/>`,
  close: `<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>`,
  code: `<path d="M8.5 7.5L4 12l4.5 4.5M15.5 7.5L20 12l-4.5 4.5"/>`,
  undo: `<path d="M9 14.5L4.5 10 9 5.5"/><path d="M4.5 10h9.2a5.8 5.8 0 0 1 0 11.6H11"/>`,
  tag: `<path d="M3.8 12.6V4.5a.7.7 0 0 1 .7-.7h8.1l7.6 7.6-8.8 8.8z"/><circle cx="8.3" cy="8.3" r="1.4"/>`,
  eye: `<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>`,
  "eye-off": `<path d="M2.5 12S6 5.5 12 5.5c1.9 0 3.6.7 5 1.6M21.5 12s-3.5 6.5-9.5 6.5c-1.9 0-3.6-.7-5-1.6"/><path d="M4 20L20 4"/>`,
  trash: `<path d="M4.5 7h15M9.5 7V4.8h5V7M6.5 7l.9 12.2a1.6 1.6 0 0 0 1.6 1.3h6a1.6 1.6 0 0 0 1.6-1.3L17.5 7"/><path d="M10 10.5v6M14 10.5v6"/>`,
  // A quick handwritten check, drawn on when a note is resolved.
  check: `<path class="stroke" d="M5 12.8c1.6 1.2 2.9 2.7 3.9 4.6C11 12.3 14.6 8 19.5 5"/>`,
} as const

export type IconName = keyof typeof PATHS

export function icon(name: IconName, ink?: string): SVGSVGElement {
  const template = document.createElement("template")
  template.innerHTML = `<svg class="icon icon-${name}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${PATHS[name]}</svg>`
  const svg = template.content.firstElementChild as SVGSVGElement
  if (ink) svg.style.setProperty("--ink-color", ink)
  return svg
}

// The page cursor for a tool: the same drawing, tip on the hotspot.
export function cursor(name: "highlighter" | "pen", ink: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#1d1b19" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"><g fill="#fffdf6">${PATHS[name].replace(/class="ink"/g, `fill="${ink}"`)}</g></svg>`
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}") 3 21, crosshair`
}
