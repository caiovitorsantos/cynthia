import { Controller } from "@hotwired/stimulus"

// Mostra só os campos do tipo de passo escolhido (data-types lista os tipos de cada campo).
export default class extends Controller {
  static targets = ["type", "field"]

  connect() {
    this.toggle()
  }

  toggle() {
    const type = this.typeTarget.value
    this.fieldTargets.forEach((field) => { field.hidden = !field.dataset.types.split(" ").includes(type) })
  }
}
