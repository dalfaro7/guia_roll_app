(() => {
  const initialize = () => {
    document.querySelectorAll('.account-editor').forEach(dialog => {
      if (dialog.dataset.bound) return;
      dialog.dataset.bound = 'true';
      const opener = document.querySelector(`[data-account-dialog="${dialog.id}"]`);
      const open = () => { if (!dialog.open) dialog.showModal(); document.body.classList.add('account-modal-open'); };
      opener?.addEventListener('click', open);
      dialog.querySelector('[data-close-account]').addEventListener('click', () => dialog.close());
      dialog.addEventListener('close', () => { document.body.classList.remove('account-modal-open'); opener?.focus(); });
      if (dialog.hasAttribute('data-reopen')) open();
    });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize);
  else initialize();
  document.addEventListener('turbo:load', initialize);
})();
