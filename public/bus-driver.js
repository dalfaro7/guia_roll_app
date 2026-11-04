(() => {
  const forms = () => document.querySelectorAll('form[data-controller="bus-driver"]');
  const busSelect = (form) => form.querySelector('select[name="bus_assignment[bus_id]"]');
  const driverSelect = (form) => form.querySelector('select[name="bus_assignment[driver_id]"]');
  const variantSelect = (form) => form.querySelector('select[name="bus_assignment[outing_variant]"]');

  const filterDrivers = (form, reset) => {
    const bus = busSelect(form);
    const driver = driverSelect(form);
    if (!bus || !driver) return;
    const selected = bus.selectedOptions[0];
    const companyId = selected && selected.dataset.companyId;
    const requiredDriverId = selected && selected.dataset.requiredDriverId;
    if (reset) driver.value = requiredDriverId || '';
    for (const option of driver.options) {
      const unavailable = requiredDriverId ? option.value !== requiredDriverId :
        (!!option.value && !!option.dataset.companyId && option.dataset.companyId !== companyId);
      option.hidden = unavailable;
      option.disabled = unavailable;
    }
    if (driver.selectedOptions[0] && driver.selectedOptions[0].disabled) driver.value = requiredDriverId || '';
    const variant = variantSelect(form);
    if (variant) {
      variant.required = selected && selected.dataset.kind === 'four_by_four';
      variant.disabled = !variant.required;
      if (!variant.required) variant.value = '';
    }
  };

  const refreshAvailability = async (form) => {
    const url = form.dataset.availableBusesUrl;
    if (!url) return;
    try {
      const location = form.querySelector('input[name="bus_assignment[location]"]').value;
      const requestUrl = new URL(url, window.location.origin);
      requestUrl.searchParams.set('location', location);
      const response = await fetch(requestUrl, { credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } });
      if (!response.ok) return;
      const data = await response.json();
      const select = busSelect(form);
      if (!select) return;
      const previous = select.value;
      select.replaceChildren();
      for (const bus of data.buses) {
        const option = new Option(bus.label, bus.id);
        option.dataset.companyId = bus.company_id;
        option.dataset.kind = bus.kind;
        option.dataset.internalFleet = bus.internal_fleet;
        option.dataset.requiredDriverId = bus.required_driver_id || '';
        select.add(option);
      }
      if (data.buses.some((bus) => String(bus.id) === previous)) select.value = previous;
      const submit = form.querySelector('input[type="submit"]');
      if (submit) submit.disabled = data.buses.length === 0;
      filterDrivers(form, select.value !== previous);
      updateQuote(form);
    } catch (_error) {
      // Server-side validations remain authoritative when availability changes.
    }
  };

  const updateQuote = async (form) => {
    const target = form.querySelector('[data-bus-driver-quote]');
    const bus = busSelect(form);
    const driver = driverSelect(form);
    if (!target || !bus || !bus.value) return;
    const url = form.dataset.driverQuoteUrl;
    if (!url) return;
    const requestUrl = new URL(url, window.location.origin);
    requestUrl.searchParams.set('bus_id', bus.value);
    requestUrl.searchParams.set('driver_id', driver.value);
    requestUrl.searchParams.set('location', form.querySelector('input[name="bus_assignment[location]"]').value);
    try {
      const response = await fetch(requestUrl, { credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } });
      const data = await response.json();
      if (!response.ok) {
        target.textContent = data.error || 'No se pudo calcular el importe.';
        return;
      }
      const dollars = (cents) => cents == null ? 'Pendiente' : '$' + (cents / 100).toFixed(2);
      target.textContent = 'Transporte: ' + dollars(data.transport_cost_cents) +
        ' · Pago directo al chofer: ' + dollars(data.driver_payment_cents) +
        ' · ' + data.explanation;
    } catch (_error) {
      target.textContent = 'No se pudo calcular el importe. Se verificará al guardar.';
    }
  };

  const initialize = () => forms().forEach((form) => {
    filterDrivers(form, true);
    updateQuote(form);
  });
  document.addEventListener('change', (event) => {
    if (event.target.matches('form[data-controller="bus-driver"] select[name="bus_assignment[bus_id]"]')) {
      filterDrivers(event.target.form, true);
      updateQuote(event.target.form);
    }
    if (event.target.matches('form[data-controller="bus-driver"] select[name="bus_assignment[driver_id]"]')) {
      updateQuote(event.target.form);
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
