import { Controller } from "@hotwired/stimulus"

// Envia o formulário quando um campo muda (ex.: filtro de status dos logs), sem handler inline (CSP).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
