import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bus", "driver"]

  connect() { this.filterDrivers() }

  filterDrivers() {
    const companyId = this.busTarget.selectedOptions[0]?.dataset.companyId
    this.driverTarget.value = "" // A changed bus cannot keep a driver from the old company.
    for (const option of this.driverTarget.options) {
      option.hidden = !!option.value && option.dataset.companyId !== companyId
      option.disabled = option.hidden
    }
  }
}
