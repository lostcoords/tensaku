import { Controller } from "@hotwired/stimulus"

// Plays the landing page's video demo while it is on screen. With reduced motion asked for, it waits
// for the play button.
export default class extends Controller {
  connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) this.element.play().catch(() => {})
      else this.element.pause()
    }, { threshold: 0.4 })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
