import { Controller } from "@hotwired/stimulus"

// Checkbox "selecionar todos" + habilita as ações só quando há algo marcado.
export default class extends Controller {
  static targets = ["all", "item", "action", "count"]

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
    this.actionTargets.forEach((action) => (action.disabled = selected === 0))
    this.countTarget.textContent = selected > 0 ? `${selected} selecionado(s)` : ""
  }
}
