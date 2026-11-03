(() => {
  const forms = () => document.querySelectorAll('form[data-controller="bus-driver"]');
  const busSelect = (form) => form.querySelector('select[name="bus_assignment[bus_id]"]');
  const driverSelect = (form) => form.querySelector('select[name="bus_assignment[driver_id]"]');

  const filterDrivers = (form, reset) => {
    const bus = busSelect(form);
    const driver = driverSelect(form);
    if (!bus || !driver) return;
    const companyId = bus.selectedOptions[0] && bus.selectedOptions[0].dataset.companyId;
    if (reset) driver.value = '';
    for (const option of driver.options) {
      const unavailable = !!option.value && option.dataset.companyId !== companyId;
      option.hidden = unavailable;
      option.disabled = unavailable;
    }
    if (driver.selectedOptions[0] && driver.selectedOptions[0].disabled) driver.value = '';
  };

  const refreshAvailability = async (form) => {
    const url = form.dataset.availableBusesUrl;
    if (!url) return;
    try {
      const response = await fetch(url, { credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } });
      if (!response.ok) return;
      const data = await response.json();
      for (const currentForm of forms()) {
        const select = busSelect(currentForm);
        if (!select) continue;
        const previous = select.value;
        select.replaceChildren();
        for (const bus of data.buses) {
          const option = new Option(bus.label, bus.id);
          option.dataset.companyId = bus.company_id;
          select.add(option);
        }
        if (data.buses.some((bus) => String(bus.id) === previous)) select.value = previous;
        const submit = currentForm.querySelector('input[type="submit"]');
        if (submit) submit.disabled = data.buses.length === 0;
        filterDrivers(currentForm, select.value !== previous);
      }
    } catch (_error) {
      // The server still rejects a bus that another operator has assigned.
    }
  };

  const initialize = () => forms().forEach((form) => filterDrivers(form, true));
  document.addEventListener('change', (event) => {
    if (event.target.matches('form[data-controller="bus-driver"] select[name="bus_assignment[bus_id]"]')) {
      filterDrivers(event.target.form, true);
    }
  });
  document.addEventListener('focusin', (event) => {
    if (event.target.matches('form[data-controller="bus-driver"] select[name="bus_assignment[bus_id]"]')) {
      refreshAvailability(event.target.form);
    }
  });
  document.addEventListener('turbo:load', initialize);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize);
  else initialize();
})();
