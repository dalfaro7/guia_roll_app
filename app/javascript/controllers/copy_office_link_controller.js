import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.urlTarget.value)
      this.statusTarget.textContent = "Enlace copiado. Ya puedes pegarlo en WhatsApp."
    } catch (_) {
      this.urlTarget.focus()
      this.urlTarget.select()
      this.statusTarget.textContent = "Seleccionamos el enlace. Mantén pulsado o usa Ctrl+C para copiarlo."
    }
  }
}
