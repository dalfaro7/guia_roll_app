const $ = id => document.getElementById(id);
let users = [], map, markers = new Map(), timer;
let speakingIdentities = [], stopMapVoice;
function radioIndicator(guideId) {
  const icon = document.createElement('i'); icon.className = 'voice-intercom'; icon.dataset.guideId = guideId;
  icon.innerHTML = '<svg viewBox="0 0 20 24" aria-hidden="true"><path d="M6 7V2m0 0 3-1M5 7h10v15H5z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 11h4m-4 3h4m-4 3h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="12" cy="20" r=".9" fill="currentColor"/></svg>';
  return icon;
}
function updateSpeaking() {
  const guides = window.KayakMapVoice?.speakingGuideIds(users, speakingIdentities) || new Set();
  document.querySelectorAll('.voice-intercom').forEach(icon => {
    const speaking = guides.has(Number(icon.dataset.guideId));
    icon.classList.toggle('speaking', speaking); icon.title = speaking ? 'Turno de voz activo' : 'Intercomunicador en reposo';
    icon.setAttribute('role','img');icon.setAttribute('aria-label',icon.title);
    icon.closest('.kayak-marker')?.classList.toggle('speaking',speaking);
    icon.closest('.user')?.classList.toggle('speaking',speaking);
  });
}
async function api(path, body) {
  const response = await fetch('/api/' + path, body ? { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content }, body: JSON.stringify(body) } : {});
  const data = await response.json(); if (!response.ok) { const error = new Error(data.error); error.status = response.status; throw error; } return data;
}
const boundsCR = [[8.0, -86.0], [11.3, -82.5]];
function fit() { if (map) map.fitBounds(boundsCR); }
function render() {
  $('total').textContent = users.length;
  $('online').textContent = users.filter(u => u.captured_at && Date.now() - u.captured_at < 180000).length;
  $('users').replaceChildren();
  for (const u of users.filter(u => u.name.toLowerCase().includes($('search').value.toLowerCase()))) {
    const button = document.createElement('button'); button.className = 'user';
    const name = document.createElement('strong'); name.textContent = u.name; name.append(radioIndicator(u.id));
    const detail = document.createElement('span');
    detail.textContent = u.captured_at ? `${Date.now() - u.captured_at < 180000 ? '● Reciente' : '○ Sin señal reciente'} · ${new Date(u.captured_at).toLocaleTimeString('es-CR')} · ±${Math.round(u.accuracy)} m` : '○ Aún sin ubicación';
    button.append(name, detail); button.onclick = () => { if (map && u.latitude != null) map.setView([u.latitude, u.longitude], 15); }; $('users').append(button);
  }
  if (!users.length) { const p = document.createElement('p'); p.textContent = 'Agrega usuarios para empezar.'; $('users').append(p); }
  if (!map) { updateSpeaking(); return; }
  for (const marker of markers.values()) marker.remove();
  markers.clear();
  for (const u of users.filter(u => u.latitude != null)) {
    const content = document.createElement('div'); content.className = 'kayak-marker' + (Date.now() - u.captured_at > 180000 ? ' stale' : '');
    content.innerHTML = '<svg width="42" height="52" viewBox="0 0 42 52" aria-hidden="true"><g transform="rotate(24 21 26)"><path d="M21 2C11 12 9 36 21 50C33 36 31 12 21 2Z" fill="#efa83e" stroke="#805020" stroke-width="1.5"/><path d="M21 6v10m0 20v10" stroke="#fff3c9" stroke-width="2" stroke-linecap="round"/><ellipse cx="21" cy="26" rx="6" ry="10" fill="#173f32"/><ellipse cx="21" cy="27" rx="3.5" ry="6" fill="#7fb2a0"/><path d="M7 32L35 20" stroke="#173f32" stroke-width="2.5" stroke-linecap="round"/><path d="M3 32l5-3 4 5-6 3zM30 18l6-3 3 5-6 3z" fill="#17634d" stroke="#fff" stroke-width=".7"/></g></svg>';
    const label = document.createElement('span'); label.className = 'marker-label'; label.textContent = u.name; label.append(radioIndicator(u.id)); content.append(label);
    const speed = document.createElement('small'); speed.className = 'marker-speed';
    if (u.speed_kmh > 90) speed.classList.add('over-limit');
    speed.textContent = Number.isFinite(u.speed_kmh) && u.speed_kmh >= 0 ? `${Date.now() - u.captured_at > 180000 ? 'Última: ' : ''}${u.speed_kmh.toLocaleString('es-CR', { maximumFractionDigits: 1 })} km/h` : 'Velocidad no disponible';
    label.append(speed);
    markers.set(u.id, L.marker([u.latitude, u.longitude], { icon: L.divIcon({ html: content, className: 'kayak-icon', iconSize: [140, 96], iconAnchor: [70, 52] }), title: u.name }).addTo(map));
  }
  updateSpeaking();
}
const crTime = timestamp => new Date(timestamp).toLocaleTimeString('es-CR', { timeZone: 'America/Costa_Rica' });
const crDate = timestamp => new Date(timestamp).toLocaleDateString('es-CR', { timeZone: 'America/Costa_Rica' });
const kmh = value => value.toLocaleString('es-CR', { maximumFractionDigits: 1 }) + ' km/h';
async function refreshAlerts() {
  const data = await api('alerts');
  const box = $('speedAlerts'); box.replaceChildren(); box.hidden = data.unreadCount === 0;
  if (!data.unreadCount) return;
  const heading = document.createElement('h2'); heading.textContent = `⚠ ${data.unreadCount} ${data.unreadCount === 1 ? 'alerta de velocidad pendiente' : 'alertas de velocidad pendientes'} · más de 90 km/h`; box.append(heading);
  for (const alert of data.items.slice(0, 5)) {
    const row = document.createElement('div'); row.className = 'alert-row';
    const info = document.createElement('p'); info.textContent = `${alert.user_name} · máxima ${kmh(alert.peak_kmh)}`;
    const time = document.createElement('small'); time.textContent = `${crDate(alert.first_at)} · ${crTime(alert.first_at)} · hora de Costa Rica`; info.append(time);
    const seen = document.createElement('button'); seen.className = 'secondary'; seen.textContent = 'Marcar como visto';
    seen.onclick = async () => { seen.disabled = true; try { await api('alerts/ack', { id: alert.id }); await refreshAlerts(); if ($('reportDialog').open) await loadReport(); } catch (error) { $('status').textContent = error.message; seen.disabled = false; } };
    row.append(info, seen); box.append(row);
  }
  const report = document.createElement('button'); report.className = 'secondary'; report.textContent = 'Consultar reporte diario'; report.onclick = showReports; box.append(report);
}
async function loadReport() {
  try {
    const data = await api('reports/speed' + ($('reportDate').value ? '?date=' + encodeURIComponent($('reportDate').value) : ''));
    $('reportDate').value = data.day; $('reportRows').replaceChildren(); $('reportError').textContent = '';
    $('reportSummary').textContent = `${data.items.length} ${data.items.length === 1 ? 'registro' : 'registros'} de exceso de velocidad el ${data.day}.`;
    for (const alert of data.items) {
      const row = document.createElement('tr');
      for (const value of [alert.user_name, crTime(alert.first_at), crTime(alert.last_at), kmh(alert.peak_kmh), alert.acknowledged_at ? 'Visto' : 'Pendiente']) { const cell = document.createElement('td'); cell.textContent = value; row.append(cell); }
      $('reportRows').append(row);
    }
  } catch (error) { $('reportError').textContent = error.message; }
}
async function showReports() { if (!$('reportDialog').open) $('reportDialog').showModal(); await loadReport(); }
$('openReports').onclick = showReports; $('closeReports').onclick = () => $('reportDialog').close(); $('reportDate').onchange = loadReport;
async function refresh() { try { users = await api('users'); render(); await refreshAlerts(); if ($('reportDialog').open) await loadReport(); $('updated').textContent = 'Panel actualizado ' + new Date().toLocaleTimeString('es-CR'); $('status').textContent = ''; } catch (error) { $('status').textContent = error.message; if (error.status === 401) { clearInterval(timer); stopMapVoice?.(); stopMapVoice = null; $('dashboard').hidden = true; $('login').hidden = false; $('reportDialog').close(); } } }
async function openDashboard(user) {
  if (user.role !== 'admin') throw new Error('Este panel es para administradores. Usa la app móvil para compartir ubicación.');
  $('login').hidden = true; $('dashboard').hidden = false;
  if (!stopMapVoice && window.KayakMapVoice) stopMapVoice = window.KayakMapVoice.start(identities => {speakingIdentities = identities;updateSpeaking();}, status => {$('mapVoiceStatus').textContent = status;});
  await refresh(); clearInterval(timer); timer = setInterval(refresh, 15000);
  if (!map) {
    if (!window.L) { $('status').textContent = 'No se pudo cargar el mapa. Revisa tu conexión y vuelve a cargar el panel.'; return; }
    $('map').replaceChildren();
    map = L.map('map').setView([9.75, -84.1], 8);
    const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' }).addTo(map);
    tiles.on('tileerror', () => { $('status').textContent = 'Algunas partes del mapa no se pudieron cargar. Revisa tu conexión.'; });
    L.control.scale({ imperial: false }).addTo(map);
    fit(); render();
  }
}
$('loginForm').onsubmit = async e => { e.preventDefault(); try { await openDashboard((await api('login', Object.fromEntries(new FormData(e.target)))).user); $('loginError').textContent = ''; e.target.reset(); } catch (error) { $('loginError').textContent = error.message; } };
$('search').oninput = render; $('fit').onclick = fit;
$('addUser').onclick = () => $('userDialog').showModal(); $('cancel').onclick = () => $('userDialog').close();
$('userForm').onsubmit = async e => { e.preventDefault(); try { await api('users', Object.fromEntries(new FormData(e.target))); e.target.reset(); $('userError').textContent = ''; $('userDialog').close(); await refresh(); } catch (error) { $('userError').textContent = error.message; } };
$('logout').hidden = true;
$('logout').onclick = async () => { try { await api('logout', {}); clearInterval(timer); location.reload(); } catch (error) { $('status').textContent = error.message; } };
api('me').then(openDashboard).catch(() => { location.href = '/users/sign_in'; });
