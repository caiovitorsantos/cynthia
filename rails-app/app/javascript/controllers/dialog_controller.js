import { Controller } from "@hotwired/stimulus"

// Abre/fecha um <dialog> nativo; clique fora da caixa fecha.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
