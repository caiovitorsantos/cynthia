import { Controller } from "@hotwired/stimulus"

// Filtra itens por chave (data-keys="mensal espera"); chave vazia mostra todos.
export default class extends Controller {
  static targets = ["button", "item"]

  select({ params: { key } }) {
    this.buttonTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.filterKeyParam === key))
    this.itemTargets.forEach((item) => { item.hidden = key !== "" && !item.dataset.keys.split(" ").includes(key) })
  }
}
