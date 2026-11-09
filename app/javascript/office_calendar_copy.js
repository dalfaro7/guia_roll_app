(() => {
  if (window.officeCalendarCopyInstalled) return
  window.officeCalendarCopyInstalled = true
  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-office-share-copy]")
    if (!button) return
    const section = button.closest("[data-office-share]")
    const input = section.querySelector("[data-office-share-url]")
    const status = section.querySelector("[data-office-share-status]")
    input.focus()
    input.select()
    input.setSelectionRange(0, input.value.length)
    let copied = false
    try { copied = document.execCommand("copy") } catch (_) {}
    if (!copied && navigator.clipboard) {
      status.textContent = "Copiando enlace…"
      try {
        await Promise.race([
          navigator.clipboard.writeText(input.value),
          new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 2000))
        ])
        copied = true
      } catch (_) {}
    }
    status.textContent = copied
      ? "Enlace copiado. Ya puedes pegarlo en WhatsApp."
      : "Seleccionamos el enlace. Mantén pulsado o usa Ctrl+C para copiarlo."
  })
})()
