import { Controller } from "@hotwired/stimulus"

// Extrai {{variaveis}} do corpo do template ao vivo, espelhando
// Template::VARIABLE_PATTERN (app/models/template.rb) em JS.
const VARIABLE_PATTERN = /(?<!@)\{\{(\w+(?::\w+)?)\}\}/g

const escapeHtml = (text) =>
  text.replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char])

// Formatação do WhatsApp: *negrito*, _itálico_, ~riscado~
const formatWhatsapp = (text) =>
  escapeHtml(text)
    .replace(/(^|\s)\*([^*\n]+)\*(?=\s|$)/gm, "$1<strong>$2</strong>")
    .replace(/(^|\s)_([^_\n]+)_(?=\s|$)/gm, "$1<em>$2</em>")
    .replace(/(^|\s)~([^~\n]+)~(?=\s|$)/gm, "$1<del>$2</del>")

export default class extends Controller {
  static targets = ["body", "output", "bubble"]
  static values = { none: String }

  connect() {
    this.update()
  }

  update() {
    const matches = [...this.bodyTarget.value.matchAll(VARIABLE_PATTERN)]
    const names = [...new Set(matches.map((match) => match[1]))]

    this.outputTarget.textContent = names.length > 0 ? names.join(", ") : this.noneValue
    this.bubbleTarget.innerHTML = formatWhatsapp(this.bodyTarget.value) || "&nbsp;"
  }
}
