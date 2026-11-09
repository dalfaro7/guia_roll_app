import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url", "status"]

  async copy() {
    let copied = false
    try {
      await navigator.clipboard.writeText(this.urlTarget.value)
      copied = true
    } catch (_) {
      this.urlTarget.focus()
      this.urlTarget.select()
      this.urlTarget.setSelectionRange(0, this.urlTarget.value.length)
      try {
        copied = document.execCommand("copy")
      } catch (_) {
        copied = false
      }
    }
    this.statusTarget.textContent = copied
      ? "Enlace copiado. Ya puedes pegarlo en WhatsApp."
      : "Seleccionamos el enlace. Mantén pulsado o usa Ctrl+C para copiarlo."
  }
}
