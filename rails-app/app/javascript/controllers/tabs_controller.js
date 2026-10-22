import { Controller } from "@hotwired/stimulus"

// Abas pela âncora da URL (#membros, #fluxos...): mostra o painel com aquele id, ou o primeiro.
// Redirecionamentos com anchor voltam direto para a aba certa.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.show(location.hash.slice(1))
  }

  select(event) {
    event.preventDefault()
    const id = event.currentTarget.hash.slice(1)
    history.replaceState(history.state, "", `#${id}`)
    this.show(id)
  }

  show(id) {
    const panel = this.panelTargets.find((p) => p.id === id) || this.panelTargets[0]
    this.panelTargets.forEach((p) => { p.hidden = p !== panel })
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", tab.hash === `#${panel.id}`))
  }
}
