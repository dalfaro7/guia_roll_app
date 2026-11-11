import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const android = /Android/i.test(navigator.userAgent)
    const standalone = ["standalone", "fullscreen", "minimal-ui"].some(mode =>
      window.matchMedia(`(display-mode: ${mode})`).matches)
    let dismissed = false
    try { dismissed = sessionStorage.getItem("android-install-dismissed") === "1" } catch (_) {}
    this.element.hidden = !android || standalone || dismissed
  }

  dismiss() {
    this.element.hidden = true
    try { sessionStorage.setItem("android-install-dismissed", "1") } catch (_) {}
  }
}
