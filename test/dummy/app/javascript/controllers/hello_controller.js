import { Controller } from "@hotwired/stimulus"

// Marks its element when connected, so tests can tell the controller survived a morph.
export default class extends Controller {
  connect() {
    this.connectedAt = Date.now()
    this.element.dataset.helloConnected = (Number(this.element.dataset.helloConnected || 0) + 1).toString()
  }
}
