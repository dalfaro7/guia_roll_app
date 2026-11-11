import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "note"]

  connect() {
    this.update()
  }

  update() {
    const penalized = this.statusTarget.value === "penalized"
    this.noteTarget.hidden = !penalized
    this.noteTarget.disabled = !penalized
  }
}
