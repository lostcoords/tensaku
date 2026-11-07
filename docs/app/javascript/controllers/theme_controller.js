import { Controller } from "@hotwired/stimulus"

const KEY = "tensaku-docs:theme"

export default class extends Controller {
  connect() {
    this.update()
  }

  toggle() {
    const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    try { localStorage.setItem(KEY, theme) } catch {}
    if (theme === "dark") document.documentElement.dataset.theme = "dark"
    else delete document.documentElement.dataset.theme
    this.update()
  }

  update() {
    const dark = document.documentElement.dataset.theme === "dark"
    this.element.setAttribute("aria-pressed", String(dark))
    this.element.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme")
  }
}
