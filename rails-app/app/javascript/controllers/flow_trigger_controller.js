import { Controller } from "@hotwired/stimulus"

// Mostra os campos do gatilho escolhido (horário ou comando).
export default class extends Controller {
  static targets = ["select", "panel"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.trigger !== this.selectTarget.value })
  }
}
