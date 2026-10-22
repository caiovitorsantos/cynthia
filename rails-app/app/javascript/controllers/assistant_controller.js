import { Controller } from "@hotwired/stimulus"

// Chat da Cynth.ia: abre/fecha, mostra "digitando…" enquanto espera, Enter envia e rola para o fim.
export default class extends Controller {
  static targets = ["panel", "scroll", "input", "typing"]

  connect() {
    this.observer = new MutationObserver(() => this.scrollDown())
    this.observer.observe(this.scrollTarget, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  toggle() {
    this.panelTarget.hidden = !this.panelTarget.hidden
    if (!this.panelTarget.hidden) {
      this.inputTarget.focus()
      this.scrollDown()
    }
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.inputTarget.form.requestSubmit()
    }
  }

  sending() {
    this.typingTarget.hidden = false
    this.scrollDown()
  }

  sent(event) {
    this.typingTarget.hidden = true
    if (event.detail.success) this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  scrollDown() {
    this.scrollTarget.scrollTop = this.scrollTarget.scrollHeight
  }
}
