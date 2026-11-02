(() => {
  const init = () => {
    const root = document.querySelector('.equity-dashboard');
    if (!root || root.dataset.bound) return;
    root.dataset.bound = 'true';
    const input = root.querySelector('#equity-guide-search');
    const rows = [...root.querySelectorAll('[data-equity-guide]')];
    const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    root.querySelector('[data-equity-search]').hidden = false;
    input.addEventListener('input', () => {
      const terms = normalize(input.value).trim().split(/\s+/).filter(Boolean);
      let visible = 0;
      rows.forEach(row => { row.hidden = !terms.every(term => normalize(row.dataset.equityGuide).includes(term)); if (!row.hidden) visible++; });
      root.querySelector('[data-equity-no-results]').hidden = visible > 0 || rows.length === 0;
      root.querySelector('[data-equity-count]').textContent = `${visible} de ${rows.length} guías`;
    });
  };
  document.addEventListener('turbo:load', init);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
