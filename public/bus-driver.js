(() => {
  const filterDrivers = (form) => {
    const bus = form.querySelector('select[name="bus_assignment[bus_id]"]');
    const driver = form.querySelector('select[name="bus_assignment[driver_id]"]');
    if (!bus || !driver) return;
    const companyId = bus.selectedOptions[0] && bus.selectedOptions[0].dataset.companyId;
    driver.value = '';
    for (const option of driver.options) {
      const unavailable = !!option.value && option.dataset.companyId !== companyId;
      option.hidden = unavailable;
      option.disabled = unavailable;
    }
  };
  const initialize = () => document.querySelectorAll('form[data-controller="bus-driver"]').forEach(filterDrivers);
  document.addEventListener('change', (event) => {
    if (event.target.matches('form[data-controller="bus-driver"] select[name="bus_assignment[bus_id]"]')) {
      filterDrivers(event.target.form);
    }
  });
  document.addEventListener('turbo:load', initialize);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize);
  else initialize();
})();
