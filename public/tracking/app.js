const $ = id => document.getElementById(id);
let users = [], map, markers = new Map(), timer, dashboardRole;
let speakingIdentities = [], stopMapVoice;
const recentUserNodes = new Map();
const userNodes = new Map(), markerNodes = new Map(), alertNodes = new Map();
let refreshInFlight = false, alertsRequest = 0, reportRequest = 0, lastReport = '';
function text(node, value) { if (node.textContent !== String(value)) node.textContent = value; }
function prune(nodes, ids, dispose = entry => entry.node.remove()) {
  for (const [id, entry] of nodes) if (!ids.has(id)) { dispose(entry); nodes.delete(id); }
}
function normalizeSearch(value) {
  return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim().replace(/\s+/g, ' ');
}
function matchesSearch(user, query) {
  const name = normalizeSearch(user.name);
  return normalizeSearch(query).split(' ').every(part => name.includes(part));
}
const suggestionNodes = new Map();
function renderSearchSuggestions() {
  const query = normalizeSearch($('search').value);
  const results = query ? users.filter(u => matchesSearch(u, query)).sort((a,b) =>
    Number(normalizeSearch(b.name).startsWith(query)) - Number(normalizeSearch(a.name).startsWith(query)) || a.name.localeCompare(b.name, 'es')) : [];
  const visible = results.slice(0, 8);
  prune(suggestionNodes, new Set(visible.map(u => u.id)));
  $('searchSuggestions').hidden = !query || !results.length;
  visible.forEach((user, index) => {
    let entry = suggestionNodes.get(user.id);
    if (!entry) {
      const node = document.createElement('button'); node.type = 'button';
      node.onclick = () => selectMapUser(user.id);
      entry = {node}; suggestionNodes.set(user.id, entry);
    }
    text(entry.node, user.name + (user.latitude == null ? ' · sin ubicación' : ''));
    if ($('searchSuggestions').children[index] !== entry.node) $('searchSuggestions').insertBefore(entry.node, $('searchSuggestions').children[index] || null);
  });
  if (query && results.length > 8) text($('userSearchStatus'), `${results.length} coincidencias · escribe más letras para precisar`);
}
function speedDisplay(u) {
  const estimate = u.speed_estimate;
  const candidate = estimate?.status === 'ready' ? estimate : estimate?.last_valid;
  const calculatedAt = candidate?.calculated_at ?? (estimate?.status === 'ready' ? u.captured_at : null);
  const age = Date.now() - calculatedAt;
  if (candidate && Number.isFinite(candidate.kmh) && calculatedAt && age >= -60000 && age <= 300000) {
    return {overLimit: candidate.kmh > 90, value: `Estimada: ${candidate.kmh.toLocaleString('es-CR', {maximumFractionDigits: 1})} km/h`,
      note: `Último cálculo · ${new Date(calculatedAt).toLocaleTimeString('es-CR', {timeZone: 'America/Costa_Rica'})}`,
      title: 'Último promedio válido de cinco minutos. Se conserva durante un máximo de cinco minutos desde su cálculo.'};
  }
  const stale = !u.captured_at || Date.now() - u.captured_at > 180000;
  const gps = Number.isFinite(u.speed_kmh) && u.speed_kmh >= 0;
  return {value: gps ? `${stale ? 'Última GPS' : 'GPS'}: ${u.speed_kmh.toLocaleString('es-CR', {maximumFractionDigits: 1})} km/h` : 'Velocidad no disponible',
    note: 'Sin cálculo válido en los últimos 5 min',
    title: 'No hay un promedio reciente disponible. La velocidad GPS, cuando aparece, es la lectura del teléfono.'};
}
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
let lastFollowPosition = null;
// Match the metric scale control (100px): its rounded bar reads about 200m.
function selectionZoom(latitude) {
  return Math.max(0, Math.min(19, Math.floor(Math.log2(156543.03392 * Math.cos(latitude * Math.PI / 180) * 100 / 200))));
}
function selectMapUser(id) {
  const user = users.find(u => String(u.id) === String(id));
  $('search').value = '';
  $('userSelect').value = user ? String(user.id) : '';
  lastFollowPosition = null;
  if (map && Number.isFinite(user?.latitude) && Number.isFinite(user?.longitude)) {
    map.setView([user.latitude, user.longitude], selectionZoom(user.latitude), {animate:false});
    lastFollowPosition = `${user.id}:${user.latitude}:${user.longitude}`;
  }
  render();
  text($('userSearchStatus'), user && user.latitude == null ? 'Este usuario aún no tiene ubicación' : '');
}
function followSelectedUser() {
  const user = users.find(u => String(u.id) === $('userSelect').value);
  if (!map || user?.latitude == null || user?.longitude == null) { lastFollowPosition = null; return; }
  const position = `${user.id}:${user.latitude}:${user.longitude}`;
  if (position !== lastFollowPosition) {
    map.panTo([user.latitude, user.longitude], {animate: false});
    lastFollowPosition = position;
  }
}
let dashboardAccountId = null;
const areaKey = () => `kayaktalkie.map-area.v1.${dashboardAccountId}`;
function savedMapArea() {
  if (dashboardAccountId == null) return null;
  try {
    const area = JSON.parse(localStorage.getItem(areaKey()));
    return area && Number.isFinite(area.lat) && Math.abs(area.lat) <= 85.051129 &&
      Number.isFinite(area.lng) && Math.abs(area.lng) <= 180 && Number.isFinite(area.zoom) && area.zoom >= 0 && area.zoom <= 19 ? area : null;
  } catch { return null; }
}
function saveMapArea() {
  if (!map || dashboardAccountId == null) return;
  const center = map.getCenter();
  const area = {lat:center.lat, lng:((center.lng + 180) % 360 + 360) % 360 - 180, zoom:map.getZoom()};
  try {
    localStorage.setItem(areaKey(), JSON.stringify(area));
    text($('mapAreaStatus'), 'Área guardada en este navegador.');
  } catch { text($('mapAreaStatus'), 'No se pudo guardar: el almacenamiento del navegador no está disponible.'); }
}
function restoreMapArea() {
  const area = savedMapArea();
  if (!area) { text($('mapAreaStatus'), 'Mueve el mapa, ajusta el zoom y pulsa Guardar área.'); return; }
  if (!map) return;
  $('search').value = ''; $('userSelect').value = ''; lastFollowPosition = null;
  map.setView([area.lat, area.lng], area.zoom, {animate:false});
  render();
  text($('mapAreaStatus'), 'Mi área · seguimiento de usuarios detenido.');
}
function fit() {
  $('userSelect').value = ''; lastFollowPosition = null;
  if (map) map.fitBounds(boundsCR);
}
function renderRecentUsers() {
  const now = Date.now();
  const recent = users.filter(u => Number.isFinite(u.latitude) && Number.isFinite(u.longitude) &&
    Number.isFinite(u.captured_at) && now - u.captured_at >= -60000 && now - u.captured_at <= 900000)
    .sort((a,b) => a.name.localeCompare(b.name, 'es') || a.id - b.id);
  prune(recentUserNodes, new Set(recent.map(u => u.id)));
  text($('recentUserCount'), recent.length);
  $('recentUsersEmpty').hidden = recent.length > 0;
  for (const u of recent) {
    let entry = recentUserNodes.get(u.id);
    if (!entry) {
      const node = document.createElement('button'); node.type = 'button'; node.className = 'recent-map-user';
      const name = document.createElement('strong'), status = document.createElement('small');
      const speed = document.createElement('small'); speed.className = 'recent-user-speed';
      node.append(name, speed, status);
      node.onclick = () => selectMapUser(u.id);
      entry = {node, name, speed, status}; recentUserNodes.set(u.id, entry);
    }
    text(entry.name, u.name);
    const display = speedDisplay(u);
    text(entry.speed, display.value.replace('Estimada:', 'Prom.:').replace('Velocidad no disponible', 'Sin velocidad'));
    entry.speed.title = `${display.title} ${display.note}`;
    entry.node.classList.toggle('speed-warning', display.overLimit === true);
    const age = Math.max(0, now - u.captured_at);
    text(entry.status, age < 60000 ? 'Ubicación hace menos de 1 min' : `Última ubicación hace ${Math.floor(age / 60000)} min`);
    entry.node.classList.toggle('recent', age < 180000);
    entry.node.setAttribute('aria-pressed', String($('userSelect').value === String(u.id)));
    // Move the existing button only when its alphabetical position changed.
    const index = recent.indexOf(u);
    if ($('recentUsers').children[index] !== entry.node) $('recentUsers').insertBefore(entry.node, $('recentUsers').children[index] || null);
  }
}
function render() {
  $('total').textContent = users.length;
  $('online').textContent = users.filter(u => u.captured_at && Date.now() - u.captured_at < 180000).length;
  const ids = new Set(users.map(u => u.id));
  prune(userNodes, ids);
  const query = normalizeSearch($('search').value);
  let matches = 0;
  for (const u of users) {
    let entry = userNodes.get(u.id);
    if (!entry) {
      const option = document.createElement('option'); option.value = String(u.id);
      entry = {node: option}; userNodes.set(u.id, entry); $('userSelect').append(option);
    }
    const matched = matchesSearch(u, query);
    entry.node.hidden = !matched; entry.node.disabled = !matched;
    text(entry.node, u.name + (u.latitude == null ? ' · sin ubicación' : ''));
    if (matched) matches++;
  }
  const selected = users.find(u => String(u.id) === $('userSelect').value);
  if (!selected || !matchesSearch(selected, query)) $('userSelect').value = '';
  text($('userSearchStatus'), matches ? '' : 'No hay usuarios que coincidan');
  renderSearchSuggestions();
  renderRecentUsers();
  if (!map) { updateSpeaking(); return; }
  const located = new Set(users.filter(u => u.latitude != null).map(u => u.id));
  prune(markerNodes, located, entry => entry.marker.remove());
  for (const id of markers.keys()) if (!located.has(id)) markers.delete(id);
  for (const u of users.filter(u => u.latitude != null)) {
    let entry = markerNodes.get(u.id);
    if (!entry) {
    const content = document.createElement('div'); content.className = 'kayak-marker';
    content.innerHTML = '<svg width="42" height="52" viewBox="0 0 42 52" aria-hidden="true"><g transform="rotate(24 21 26)"><path d="M21 2C11 12 9 36 21 50C33 36 31 12 21 2Z" fill="#efa83e" stroke="#805020" stroke-width="1.5"/><path d="M21 6v10m0 20v10" stroke="#fff3c9" stroke-width="2" stroke-linecap="round"/><ellipse cx="21" cy="26" rx="6" ry="10" fill="#173f32"/><ellipse cx="21" cy="27" rx="3.5" ry="6" fill="#7fb2a0"/><path d="M7 32L35 20" stroke="#173f32" stroke-width="2.5" stroke-linecap="round"/><path d="M3 32l5-3 4 5-6 3zM30 18l6-3 3 5-6 3z" fill="#17634d" stroke="#fff" stroke-width=".7"/></g></svg>';
    const label = document.createElement('span'); label.className = 'marker-label'; label.tabIndex = 0;
    const name = document.createTextNode(''); label.append(name, radioIndicator(u.id)); content.append(label);
    const marker = L.marker([u.latitude, u.longitude], {icon: L.divIcon({html: content, className: 'kayak-icon', iconSize: [140, 96], iconAnchor: [70, 52]}), title: u.name, riseOnHover: true, riseOffset: 10000}).addTo(map);
    entry = {marker, content, name}; markerNodes.set(u.id, entry); markers.set(u.id, marker);
    }
    const current = entry.marker.getLatLng();
    if (current.lat !== u.latitude || current.lng !== u.longitude) entry.marker.setLatLng([u.latitude, u.longitude]);
    if (entry.name.nodeValue !== u.name) entry.name.nodeValue = u.name;
    entry.marker.options.title = u.name;
    const element = entry.marker.getElement(); if (element && element.title !== u.name) element.title = u.name;
    entry.content.classList.toggle('stale', Date.now() - u.captured_at > 180000);
    entry.content.classList.toggle('speed-warning', speedDisplay(u).overLimit === true);
  }
  followSelectedUser();
  updateSpeaking();
}
const crTime = timestamp => new Date(timestamp).toLocaleTimeString('es-CR', { timeZone: 'America/Costa_Rica' });
const crDate = timestamp => new Date(timestamp).toLocaleDateString('es-CR', { timeZone: 'America/Costa_Rica' });
const speedSource = source => source === 'estimated' ? 'Promedio calculado' : 'GPS del teléfono';
const kmh = value => value.toLocaleString('es-CR', { maximumFractionDigits: 1 }) + ' km/h';
async function refreshAlerts() {
  const request = ++alertsRequest, data = await api('alerts');
  if (request !== alertsRequest) return;
  const box = $('speedAlerts'); box.hidden = data.unreadCount === 0;
  let heading = box.querySelector('h2'), report = box.querySelector('.report-link');
  if (!heading) {
    heading = document.createElement('h2'); box.append(heading);
    report = document.createElement('button'); report.className = 'secondary report-link'; report.textContent = 'Consultar reporte diario'; report.onclick = showReports; box.append(report);
  }
  text(heading, `⚠ ${data.unreadCount} ${data.unreadCount === 1 ? 'alerta de velocidad pendiente' : 'alertas de velocidad pendientes'} · más de 90 km/h`);
  const items = data.unreadCount ? data.items.slice(0, 5) : [];
  prune(alertNodes, new Set(items.map(alert => alert.id)));
  for (const alert of items) {
    let entry = alertNodes.get(alert.id);
    if (!entry) {
      const row = document.createElement('div'); row.className = 'alert-row';
      const info = document.createElement('p'), name = document.createTextNode(''), time = document.createElement('small'); info.append(name, time);
      const seen = document.createElement('button'); seen.className = 'secondary'; seen.textContent = 'Marcar como visto';
      seen.onclick = async () => { seen.disabled = true; try { await api('alerts/ack', {id: alert.id}); await refreshAlerts(); if ($('reportDialog').open) await loadReport(); } catch (error) { $('status').textContent = error.message; } finally { seen.disabled = false; } };
      row.append(info, seen); box.insertBefore(row, report); entry = {node: row, name, time}; alertNodes.set(alert.id, entry);
    }
    const value = `${alert.user_name} · ${speedSource(alert.source)} · máxima ${kmh(alert.peak_kmh)}`; if (entry.name.nodeValue !== value) entry.name.nodeValue = value;
    text(entry.time, `${crDate(alert.first_at)} · ${crTime(alert.first_at)} · hora de Costa Rica`);
  }
}
async function loadReport() {
  const request = ++reportRequest, selectedDate = $('reportDate').value;
  try {
    const data = await api('reports/speed' + ($('reportDate').value ? '?date=' + encodeURIComponent($('reportDate').value) : ''));
    if (request !== reportRequest || $('reportDate').value !== selectedDate || !$('reportDialog').open) return;
    const signature = JSON.stringify(data); if (signature === lastReport) return; lastReport = signature;
    if (!$('reportDate').value) $('reportDate').value = data.day; $('reportRows').replaceChildren(); $('reportError').textContent = '';
    $('reportSummary').textContent = `${data.items.length} ${data.items.length === 1 ? 'registro' : 'registros'} de exceso de velocidad el ${data.day}.`;
    for (const alert of data.items) {
      const row = document.createElement('tr');
      for (const value of [alert.user_name, speedSource(alert.source), crTime(alert.first_at), crTime(alert.last_at), kmh(alert.peak_kmh), alert.acknowledged_at ? 'Visto' : 'Pendiente']) { const cell = document.createElement('td'); cell.textContent = value; row.append(cell); }
      $('reportRows').append(row);
    }
  } catch (error) { if (request === reportRequest && $('reportDate').value === selectedDate && $('reportDialog').open) $('reportError').textContent = error.message; }
}
async function showReports() { if (!$('reportDialog').open) $('reportDialog').showModal(); await loadReport(); }
$('openReports').onclick = showReports; $('closeReports').onclick = () => $('reportDialog').close(); $('reportDate').onchange = loadReport;
async function refresh() { if (refreshInFlight) return; refreshInFlight = true; try { users = await api('users'); render(); if (dashboardRole === 'admin') await refreshAlerts(); if ($('reportDialog').open) await loadReport(); $('updated').textContent = 'Panel actualizado ' + new Date().toLocaleTimeString('es-CR'); $('status').textContent = ''; } catch (error) { $('status').textContent = error.message; if (error.status === 401) { clearInterval(timer); stopMapVoice?.(); stopMapVoice = null; $('dashboard').hidden = true; location.href = '/kayaktalkie/login'; $('reportDialog').close(); } } finally { refreshInFlight = false; } }
async function openDashboard(user) {
  dashboardRole = user.role; dashboardAccountId = user.id;
  if (!['admin','operator'].includes(user.role)) throw new Error('Este panel es para administradores. Usa la app móvil para compartir ubicación.');
  $('dashboard').hidden = false;
  if (!stopMapVoice && window.KayakMapVoice) stopMapVoice = window.KayakMapVoice.start(identities => {speakingIdentities = identities;updateSpeaking();}, status => {$('mapVoiceStatus').textContent = status;});
  await refresh(); clearInterval(timer); timer = setInterval(refresh, 15000);
  if (!map) {
    if (!window.L) { $('status').textContent = 'No se pudo cargar el mapa. Revisa tu conexión y vuelve a cargar el panel.'; return; }
    $('map').replaceChildren();
    map = L.map('map').setView([9.75, -84.1], 8);
    const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' }).addTo(map);
    tiles.on('tileerror', () => { $('status').textContent = 'Algunas partes del mapa no se pudieron cargar. Revisa tu conexión.'; });
    L.control.scale({ imperial: false, maxWidth: 100 }).addTo(map);
    fit(); render();
  }
}
$('userSelect').onchange = () => selectMapUser($('userSelect').value);
$('search').onkeydown = event => {
  if (event.key === 'Escape') { $('search').value = ''; render(); return; }
  if (event.key !== 'Enter') return;
  const query = normalizeSearch($('search').value);
  if (!query) return;
  const matches = users.filter(u => matchesSearch(u, query));
  if (matches.length === 1) { event.preventDefault(); selectMapUser(matches[0].id); }
  else text($('userSearchStatus'), matches.length ? 'Selecciona un usuario de la lista' : 'No hay usuarios que coincidan');
};
$('search').oninput = render; $('fit').onclick = fit;
$('myArea').onclick = restoreMapArea; $('saveArea').onclick = saveMapArea;
api('me').then(openDashboard).catch(() => { location.href = '/kayaktalkie/login'; });
