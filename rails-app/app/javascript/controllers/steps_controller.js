import { Controller } from "@hotwired/stimulus"

// Lista de passos do fluxo: adicionar (a partir do <template>), remover e reordenar.
// A ordem no formulário é a ordem dos passos salvos.
export default class extends Controller {
  static targets = ["list", "template"]
  static values = { label: String }

  connect() {
    this.renumber()
  }

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.renumber()
    this.listTarget.lastElementChild.querySelector("select")?.focus()
  }

  remove(event) {
    event.currentTarget.closest("li").remove()
    this.renumber()
  }

  up(event) {
    const step = event.currentTarget.closest("li")
    step.previousElementSibling?.before(step)
    this.renumber()
  }

  down(event) {
    const step = event.currentTarget.closest("li")
    step.nextElementSibling?.after(step)
    this.renumber()
  }

  renumber() {
    this.listTarget.querySelectorAll("[data-step-number]").forEach((number, index) => { number.textContent = this.labelValue.replace("%{n}", index + 1) })
  }
}
