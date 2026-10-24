import { Controller } from "@hotwired/stimulus"

// Aviso flutuante: some sozinho depois de `duration` ms (ou no ×), com fade.
export default class extends Controller {
  static values = { duration: { type: Number, default: 6000 } }

  connect() {
    this.timer = setTimeout(() => this.close(), this.durationValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  close() {
    this.element.classList.add("opacity-0")
    setTimeout(() => this.element.remove(), 300)
  }
}
