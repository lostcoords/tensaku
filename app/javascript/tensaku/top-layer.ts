// Dialogs opened with showModal() and popovers sit in the browser's top layer, above any z-index, and a
// modal dialog makes the rest of the page inert: nothing outside it takes clicks or focus. While one is
// open, the overlay's host moves inside the topmost modal dialog or auto popover and is shown as a
// popover itself, last, so it draws above everything, takes clicks and focus, and a click on it counts
// as inside the app's popover, which stays open. With nothing open it goes back to <html>. Browsers
// without the Popover API keep it on <html>, under the dialog.

import { host } from "./ui"

const supported = typeof host.showPopover === "function"
if (supported) host.popover = "manual"

// The open dialogs and popovers, in the order they opened, which is their order in the top layer.
let opened: Element[] = []
let raisedOver: Element | null = null
let scope: Element | null = null
const listeners: (() => void)[] = []

// The topmost open modal dialog. Only what is inside it can be used, so select mode's arrow keys, edit
// mode's outlines and the pins stay in it.
export const modalScope = () => scope
export const outsideScope = (element: Element) => Boolean(scope && !scope.contains(element))
export const onScopeChange = (listener: () => void) => { listeners.push(listener) }

function openNow(): Element[] {
  try {
    return Array.from(document.querySelectorAll("dialog:modal, :popover-open")).filter((element) => element !== host)
  } catch {
    return []
  }
}

const last = (elements: Element[], test: (element: Element) => boolean) => [...elements].reverse().find(test)
const holdsHost = (element: Element) => element.matches("dialog:modal") || ["auto", "hint"].includes((element as HTMLElement).popover ?? "")

// closing: a popover about to close, which the host leaves before it hides.
function sync(closing?: Element) {
  if (!supported) {
    if (!host.isConnected) document.documentElement.append(host)
    return
  }
  const now = openNow().filter((element) => element !== closing)
  opened = [...opened.filter((element) => now.includes(element)), ...now.filter((element) => !opened.includes(element))]
  const container = last(opened, holdsHost) ?? document.documentElement
  if (host.parentNode !== container) container.append(host)

  const top = opened.at(-1) ?? null
  const raised = host.matches(":popover-open")
  if (!top) {
    if (raised) host.hidePopover()
  } else if (!raised || top !== raisedOver) {
    // Shown again, so it is last in the top layer, above what opened since.
    if (raised) host.hidePopover()
    host.showPopover()
  }
  raisedOver = top

  const modal = last(opened, (element) => element.matches("dialog:modal")) ?? null
  if (modal !== scope) {
    scope = modal
    listeners.forEach((listener) => listener())
  }
}

// Dialogs open and close through their open attribute, and leave the top layer when removed; popovers
// say so with toggle events, which don't bubble, so they are heard while capturing.
export function watchTopLayer() {
  sync()
  new MutationObserver((records) => {
    if (records.some((record) => record.type === "attributes") || !host.isConnected || opened.some((element) => !element.isConnected)) sync()
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["open"] })
  document.addEventListener("toggle", (event) => { if (event.target !== host) sync() }, true)
  document.addEventListener("beforetoggle", (event) => {
    const target = event.target as Element
    if (target !== host && (event as ToggleEvent).newState === "closed" && target.contains(host)) sync(target)
  }, true)
}
