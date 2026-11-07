import { Controller } from "@hotwired/stimulus"

// Counts connects and disconnects, so tests can tell the controller survived a morph.
export default class extends Controller {
  connect() {
    window.helloConnects = (window.helloConnects || 0) + 1
  }

  disconnect() {
    window.helloDisconnects = (window.helloDisconnects || 0) + 1
  }
}
