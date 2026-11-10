(() => {
  const init = () => {
    const root = document.querySelector('.equity-dashboard');
    if (!root || root.equityBound) return;
    root.equityBound = 'true';

    const search = root.querySelector('#equity-guide-search');
    const priority = root.querySelector('#equity-guide-priority');
    const pageSize = root.querySelector('#equity-guide-page-size');
    const rows = [...root.querySelectorAll('[data-equity-guide]')];
    const empty = root.querySelector('[data-equity-no-results]');
    const count = root.querySelector('[data-equity-count]');
    const pageLabel = root.querySelector('[data-equity-page]');
    const previous = root.querySelector('[data-equity-prev]');
    const next = root.querySelector('[data-equity-next]');
    const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    let page = 0;

    const render = () => {
      const terms = normalize(search.value).trim().split(/\s+/).filter(Boolean);
      const matching = rows.filter(row =>
        (!priority.value || row.dataset.equityPriority === priority.value) &&
        terms.every(term => normalize(row.dataset.equityGuide).includes(term))
      );
      const size = pageSize.value === 'all' ? Math.max(matching.length, 1) : Number(pageSize.value);
      const pages = Math.max(1, Math.ceil(matching.length / size));
      page = Math.min(page, pages - 1);
      rows.forEach(row => { row.hidden = true; });
      matching.slice(page * size, (page + 1) * size).forEach(row => { row.hidden = false; });

      empty.hidden = matching.length > 0 || rows.length === 0;
      const start = matching.length ? page * size + 1 : 0;
      const end = Math.min((page + 1) * size, matching.length);
      count.textContent = `Mostrando ${start}–${end} de ${matching.length} guías`;
      pageLabel.textContent = `Página ${page + 1} de ${pages}`;
      previous.disabled = page === 0;
      next.disabled = page >= pages - 1;
    };

    search.addEventListener('input', () => { page = 0; render(); });
    priority.addEventListener('change', () => { page = 0; render(); });
    pageSize.addEventListener('change', () => { page = 0; render(); });
    previous.addEventListener('click', () => { page--; render(); });
    next.addEventListener('click', () => { page++; render(); });
    root.querySelector('[data-equity-controls]').hidden = false;
    root.querySelector('[data-equity-pagination]').hidden = false;
    render();
  };
  document.addEventListener('turbo:load', init);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
