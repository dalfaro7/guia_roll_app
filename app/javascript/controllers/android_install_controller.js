import { Controller } from "@hotwired/stimulus"

// Keep the browser event across Turbo page changes, including before connect().
let installPrompt = null
let installed = false
window.addEventListener("beforeinstallprompt", event => {
  if (!/Android/i.test(navigator.userAgent)) return
  event.preventDefault()
  installPrompt = event
  window.dispatchEvent(new Event("android-install:changed"))
})
window.addEventListener("appinstalled", () => {
  installed = true
  installPrompt = null
  window.dispatchEvent(new Event("android-install:changed"))
})

export default class extends Controller {
  static targets = ["install", "status"]

  connect() {
    this.refresh = this.update.bind(this)
    window.addEventListener("android-install:changed", this.refresh)
    this.update()
  }

  disconnect() {
    window.removeEventListener("android-install:changed", this.refresh)
  }

  update() {
    const android = /Android/i.test(navigator.userAgent)
    const standalone = ["standalone", "fullscreen", "minimal-ui"].some(mode =>
      window.matchMedia(`(display-mode: ${mode})`).matches)
    let dismissed = false
    try { dismissed = sessionStorage.getItem("android-install-dismissed") === "1" } catch (_) {}
    this.element.hidden = !android || standalone || dismissed || installed
    this.installTarget.hidden = !installPrompt
  }

  async install() {
    const prompt = installPrompt
    if (!prompt) return
    installPrompt = null
    this.installTarget.disabled = true
    this.statusTarget.textContent = ""
    try {
      await prompt.prompt()
      const choice = await prompt.userChoice
      if (choice.outcome === "accepted") {
        this.element.hidden = true
      } else {
        this.statusTarget.textContent = "Puedes instalarla más adelante desde el menú del navegador."
      }
    } catch (_) {
      this.statusTarget.textContent = "Abre el menú del navegador y elige Instalar aplicación o Añadir a la pantalla de inicio."
    } finally {
      this.installTarget.disabled = false
      this.installTarget.hidden = !installPrompt
    }
  }

  dismiss() {
    this.element.hidden = true
    try { sessionStorage.setItem("android-install-dismissed", "1") } catch (_) {}
  }
}
