import { Controller } from "@hotwired/stimulus"

// Busca periodicamente uma resposta Turbo Stream e aplica no DOM.
// Usado em /connection para atualizar o status/QR Code enquanto qr_pending.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async refresh() {
    const response = await fetch(this.urlValue, {
      headers: { Accept: "text/vnd.turbo-stream.html" },
    })

    if (!response.ok) return

    const html = await response.text()
    Turbo.renderStreamMessage(html)
  }
}
