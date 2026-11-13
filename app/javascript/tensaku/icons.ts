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
  history: `<path d="M4 12a8 8 0 1 0 2.4-5.7"/><path d="M4 4.5v3.8h3.8"/><path d="M12 8v4.3l2.8 1.8"/>`,
  sliders: `<path d="M4 8h9M17 8h3M4 16h3M11 16h9"/><circle cx="15" cy="8" r="2.2"/><circle cx="9" cy="16" r="2.2"/>`,
  pause: `<path d="M9 5.5v13M15 5.5v13"/>`,
  play: `<path d="M8 5.5l10 6.5-10 6.5z"/>`,
  // A folded paper plane: notes going to an agent. In flight, with two hand-drawn speed strokes, while
  // an agent listens.
  plane: `<path d="M20.5 3.5L3.5 10.4l6.6 3 3 6.6z"/><path d="M10.1 13.4l10.4-9.9"/>`,
  "plane-flying": `<path class="ink" d="M20.5 3.5L3.5 10.4l6.6 3 3 6.6z"/><path d="M10.1 13.4l10.4-9.9"/><path d="M3 16.5l3-1.2M4.5 20l3.4-1.6" stroke-width="1.6"/>`,
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

// The logo, a hanamaru (the flower a teacher draws on good work), in one stroke. Thicker and with less
// spiral than docs/app/assets/images/hanamaru.svg, so it stays clear at this size.
export function logo(): SVGSVGElement {
  const template = document.createElement("template")
  template.innerHTML = `<svg class="logo" viewBox="0 3.65 100 100" aria-hidden="true" focusable="false"><path d="M48.2 48.6L48.9 47.2L49.7 46.4L51.1 45.6L52.5 45.3L54.1 45.3L56.9 46.3L58.5 47.6L60.2 49.9L60.5 50.6L61.3 53.8L61.1 57.4L59.7 61L59.1 61.9L57.8 63.6L56.3 65.1L54.4 66.4L51.2 67.9L48.8 68.5L44.9 68.7L42.3 68.4L39.6 67.7L37 66.5L34.5 65L32.2 63L30.1 60.7L27.6 56.6L26.4 53.5L26 51.8L25.5 48.4L25.4 44.9L25.9 41.3L26.4 39.5L28.5 34.2L30.6 30.9L33.2 27.9L36.3 25.2L38 24L39.8 22.9L43.7 21.2L47.8 19.9L50 19.5L50.7 16.8L51.5 15.6L53.2 13.8L55 12.6L57.8 11.4L59.8 10.8L61.7 10.5L64.7 10.4L69.5 11.2L74 13L75.7 14L78 15.8L80.7 18.6L82.4 21L83.3 22.7L84.1 24.5L85.1 28.4L85.3 30.3L85.1 33.4L84.7 35.4L83.9 37.5L82.3 39.8L80.3 41.2L83.6 42.5L85.4 43.6L86.9 45L88.7 47.2L90.4 50.6L91 52.4L91.7 56.9L91.7 58.8L90.9 63.4L90 66L89.2 67.7L86.6 71.5L83.9 74L82.4 75.1L79 76.8L77.2 77.4L74.2 77.8L73.2 77.8L70.9 77.4L70.6 78.2L68.8 77L69.9 79.8L70 81.2L69.3 84.7L68.4 86.7L67.3 88.4L64.6 91.5L62.2 93.3L58.7 95.2L56.8 95.9L53.9 96.6L48.9 96.9L44 96.1L40.3 94.7L37.7 93.2L35.3 91.4L33.9 89.9L32.1 87.5L31.1 85.6L30.1 82.3L30 81L31 77L28.5 78L25.1 78.3L22.1 77.9L18.5 76.5L15.3 74.4L13.2 72.5L11.4 70.3L9.9 67.9L9.1 66.2L8.2 63.5L7.5 59.8L7.5 56L8.2 52.3L9.6 48.7L12.4 44.7L15.8 42.2L17 41.7L17.4 41.1L19.3 40.9L17.9 39.7L17 38.6L15.6 35.4L15.1 32.4L15.3 28.4L16.3 24.7L18 21.2L20.3 18.1L23.9 14.9L27.2 12.9L29.9 11.8L31.8 11.3L35.6 10.8L39.5 11.1L42.4 11.8L45.2 13.1L46.1 13.7L47.8 15.1L49.4 17L50.1 18.6L50.9 16.6L51.7 15.4L53.4 13.7L55.2 12.5L58.9 11"/></svg>`
  return template.content.firstElementChild as SVGSVGElement
}

// The page cursor for a tool: the same drawing, tip on the hotspot.
export function cursor(name: "highlighter" | "pen", ink: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#1d1b19" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"><g fill="#fffdf6">${PATHS[name].replace(/class="ink"/g, `fill="${ink}"`)}</g></svg>`
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}") 3 21, crosshair`
}
