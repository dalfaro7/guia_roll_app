document.addEventListener("click", async (event) => {
  const button = event.target instanceof Element &&
    event.target.closest("[data-copy-distribution]");
  if (!button) return;

  const status = button.nextElementSibling;
  const url = button.dataset.copyDistribution;
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(url);
    } else {
      const input = document.createElement("textarea");
      input.value = url;
      input.style.position = "fixed";
      input.style.opacity = "0";
      document.body.appendChild(input);
      input.select();
      const copied = document.execCommand("copy");
      input.remove();
      if (!copied) throw new Error("Clipboard unavailable");
    }
    status.textContent = "Enlace copiado";
  } catch (_) {
    status.textContent = "No se pudo copiar. Copia la dirección del navegador.";
  }
});
