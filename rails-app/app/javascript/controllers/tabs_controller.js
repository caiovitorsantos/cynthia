import { Controller } from "@hotwired/stimulus"

// Abas pela âncora da URL (#membros, #fluxos...): mostra o painel com aquele id, ou o primeiro.
// WHA-21: o Turbo segue o redirect via fetch e perde a âncora (#fluxos) depois de salvar um formulário.
// Por isso a ordem é: âncora > ?tab= > última aba vista nesta página (sessionStorage, por caminho) > a que o
// servidor já marcou. ponytail: sessionStorage acerta o caso comum (abriu a aba, editou, salvou); o redirect
// com ?tab= no controller Rails torna isso independente do histórico.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const id = location.hash.slice(1) || new URLSearchParams(location.search).get("tab") || this.remembered
    if (id) this.show(id)
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
    try { sessionStorage.setItem(this.key, panel.id) } catch {}
  }

  get remembered() {
    try { return sessionStorage.getItem(this.key) } catch { return null }
  }

  get key() {
    return `tabs:${location.pathname}`
  }
}
