import { Controller } from "@hotwired/stimulus"

// Seletor de horário da rotina: monta o cron (ou a data do envio único) a partir de
// "todo dia / toda semana / todo mês + horário". "Avançado" deixa editar o cron direto.
export default class extends Controller {
  static targets = ["mode", "section", "weekday", "monthday", "time", "cron", "runAt"]

  connect() {
    this.update()
  }

  update() {
    const mode = this.modeTarget.value
    this.sectionTargets.forEach((section) => { section.hidden = !section.dataset.modes.split(" ").includes(mode) })

    if (mode === "custom") return (this.runAtTarget.value = "")
    if (mode === "once") return (this.cronTarget.value = "")

    this.runAtTarget.value = ""
    const [hour, minute] = (this.timeTarget.value || "09:00").split(":").map(Number)
    const days = this.weekdayTargets.filter((day) => day.checked).map((day) => day.value)
    const weekday = mode === "weekly" && days.length ? days.join(",") : "*"
    const monthday = mode === "monthly" ? Number(this.monthdayTarget.value) || 1 : "*"
    this.cronTarget.value = `${minute} ${hour} ${monthday} * ${weekday}`
  }
}
