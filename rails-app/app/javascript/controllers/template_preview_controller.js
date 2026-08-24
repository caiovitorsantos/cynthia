import { Controller } from "@hotwired/stimulus"

// Extrai {{variaveis}} do corpo do template ao vivo, espelhando
// Template::VARIABLE_PATTERN (app/models/template.rb) em JS.
const VARIABLE_PATTERN = /(?<!@)\{\{(\w+)\}\}/g

export default class extends Controller {
  static targets = ["body", "output"]

  connect() {
    this.update()
  }

  update() {
    const matches = [...this.bodyTarget.value.matchAll(VARIABLE_PATTERN)]
    const names = [...new Set(matches.map((match) => match[1]))]

    this.outputTarget.textContent = names.length > 0 ? names.join(", ") : "nenhuma variável detectada"
  }
}
