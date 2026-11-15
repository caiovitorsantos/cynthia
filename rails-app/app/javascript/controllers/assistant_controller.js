import { Controller } from "@hotwired/stimulus"

// Chat da Cynth.ia: abre/fecha como diálogo não modal, mostra "digitando…" enquanto espera,
// Enter envia, rola para o fim e anuncia resposta, erro e desfecho de proposta no leitor de tela.
export default class extends Controller {
  static targets = ["panel", "scroll", "input", "typing", "status", "launcher", "outcome"]

  connect() {
    this.observer = new MutationObserver(() => this.contentChanged())
    this.observer.observe(this.scrollTarget, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.launcherTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.focus()
    this.scrollDown()
  }

  // A23: Esc, "×" ou o botão redondo fecham; o foco volta ao botão que abriu.
  close() {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    this.launcherTarget.setAttribute("aria-expanded", "false")
    this.launcherTarget.focus()
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.inputTarget.form.requestSubmit()
    }
  }

  sending() {
    this.awaitingReply = true
    this.typingTarget.hidden = false
    this.announce(this.typingTarget.textContent)
    this.scrollDown()
  }

  sent(event) {
    this.typingTarget.hidden = true
    if (event.detail.success) this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  // A22: a conversa é reescrita inteira a cada turno; anuncia só o último balão da Cynth.ia (ou o erro).
  contentChanged() {
    this.scrollDown()
    if (!this.awaitingReply) return
    const replies = this.scrollTarget.querySelectorAll("[data-assistant-reply]")
    if (!replies.length) return
    this.awaitingReply = false
    this.announce(replies[replies.length - 1].textContent)
  }

  // A24: ao Confirmar/Cancelar o cartão é trocado e o botão some; o foco vai para o novo status
  // e ele é anunciado. Só age se o foco caiu no <body> (carregar a conversa não rouba o foco).
  outcomeTargetConnected(element) {
    if (this.panelTarget.hidden) return
    if (document.activeElement && document.activeElement !== document.body) return
    element.focus()
    this.announce(element.textContent)
  }

  announce(text) {
    this.statusTarget.textContent = text.replace(/\s+/g, " ").trim()
  }

  scrollDown() {
    this.scrollTarget.scrollTop = this.scrollTarget.scrollHeight
  }
}
