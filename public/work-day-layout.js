(() => {
  function prepareDayLayout() {
    const page = document.querySelector('.work-day-three-column');
    if (!page || page.dataset.layoutReady) return;
    page.dataset.layoutReady = 'true';
    const wide = matchMedia('(min-width: 1101px)');
    const panels = page.querySelectorAll('.day-sidebar-disclosure');
    const adapt = () => panels.forEach(panel => { panel.open = wide.matches; });
    adapt(); wide.addEventListener('change', adapt);
    page.querySelectorAll('.work-day-nav a').forEach(link => link.addEventListener('click', () => {
      const target = page.querySelector(link.hash);
      if (target instanceof HTMLDetailsElement) target.open = true;
      if (link.hash === '#day-overview') page.querySelector('.day-sidebar-right details').open = true;
    }));
    document.addEventListener('turbo:before-cache', () => { wide.removeEventListener('change', adapt); delete page.dataset.layoutReady; }, {once:true});
  }
  document.addEventListener('DOMContentLoaded', prepareDayLayout);
  document.addEventListener('turbo:load', prepareDayLayout);
})();
