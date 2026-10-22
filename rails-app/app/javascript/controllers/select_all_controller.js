import { Controller } from "@hotwired/stimulus"

// Checkbox "selecionar todos" + barra de ações que só aparece quando há algo marcado.
export default class extends Controller {
  static targets = ["all", "item", "bar", "count"]

  connect() {
    this.refresh()
  }

  toggleAll() {
    this.itemTargets.forEach((item) => (item.checked = this.allTarget.checked))
    this.refresh()
  }

  refresh() {
    const selected = this.itemTargets.filter((item) => item.checked).length

    this.allTarget.checked = selected > 0 && selected === this.itemTargets.length
    this.allTarget.indeterminate = selected > 0 && selected < this.itemTargets.length
    this.barTarget.hidden = selected === 0
    this.countTarget.textContent = selected === 1 ? "1 grupo selecionado" : `${selected} grupos selecionados`
  }
}
