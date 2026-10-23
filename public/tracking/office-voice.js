(() => {
  const $ = id => document.getElementById(id);
  if (!$('voicePanel')) return;
  let room = null, held = false, lease = null, timer = null, muted = false, claiming = false, connecting = false, connected = false, keyboardHeld = false;
  function error(message = '') { $('voiceError').textContent = message; $('voiceError').hidden = !message; }
  function buttonState(label, hint) { $('talkLabel').textContent = label; $('talkHint').textContent = hint; $('voiceTalk').setAttribute('aria-label', label === 'CONECTAR' ? 'Conectar al canal' : `${label}: ${hint}`); }
  function remoteSpeakers(speakers = []) {
    const others = speakers.filter(p => p.identity !== room?.localParticipant.identity);
    $('remoteIndicator').classList.toggle('speaking', others.length > 0);
    $('remoteSpeaker').textContent = others.length ? `Habla: ${others.map(p => p.name || 'Participante').join(', ')}` : 'Nadie está hablando';
  }
  function resting() {
    $('voiceTalk').classList.remove('held');
    buttonState(connected ? 'HABLAR' : 'CONECTAR', connected ? 'Mantén pulsado para transmitir' : 'Toca para activar la recepción');
    $('microphoneState').textContent = 'Micrófono apagado'; $('microphoneState').classList.remove('transmitting');
  }
  async function api(action, body) {
    const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch('/api/voice/' + action, { method: body ? 'POST' : 'GET', headers: {'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content}, ...(body ? {body: JSON.stringify({...body, channel_id: $('voiceChannel')?.value})} : {}), signal: controller.signal });
      const text = await response.text(); let data = {};
      try { data = text ? JSON.parse(text) : {}; } catch { throw new Error('Respuesta inesperada del servidor. Recarga la página.'); }
      if (!response.ok) throw new Error(data.error || (response.status === 403 ? 'La sesión cambió. Recarga esta página para continuar.' : 'No se pudo conectar al canal.'));
      return data;
    } finally { clearTimeout(timeout); }
  }
  async function release() {
    held = false; keyboardHeld = false; clearTimeout(timer); const previousLease = lease; lease = null; resting();
    try { await room?.localParticipant.setMicrophoneEnabled(false); }
    finally { if (previousLease) await api('release', {lease: previousLease}).catch(e => error(e.message)); }
  }
  async function leave() {
    connected = false; await release().catch(() => {}); const previous = room; room = null;
    await previous?.disconnect(); $('voiceAudio').replaceChildren();
    $('voiceJoin').disabled = false; if($('voiceChannel'))$('voiceChannel').disabled = false; for (const id of ['voiceMute','voiceLeave']) $(id).disabled = true;
    $('voiceTalk').disabled = false; $('connectionLight').classList.remove('connected');
    $('voiceStatus').textContent = 'Desconectado'; remoteSpeakers(); resting();
  }
  async function join() {
    if (connecting || connected) return;
    if($('voiceChannel') && !$('voiceChannel').value) { error('El administrador debe asignarte un canal.'); return; }
    if($('channelTitle') && $('voiceChannel'))$('channelTitle').textContent=$('voiceChannel').selectedOptions[0]?.textContent || 'Canal autorizado';
    connecting = true; $('voiceMenu').open = false; error(); $('voiceJoin').disabled = true; if($('voiceChannel'))$('voiceChannel').disabled = true; $('voiceTalk').disabled = true;
    buttonState('CONECTANDO', 'Preparando el canal de voz'); $('voiceStatus').textContent = 'Conectando…';
    try {
      const access = await api('join', {}); const next = new LivekitClient.Room(); room = next;
      next.on(LivekitClient.RoomEvent.TrackSubscribed, track => {if (track.kind === 'audio') { const element = track.attach(); element.autoplay = true; element.muted = muted; $('voiceAudio').append(element); }});
      next.on(LivekitClient.RoomEvent.TrackUnsubscribed, track => track.detach().forEach(element => element.remove()));
      next.on(LivekitClient.RoomEvent.ActiveSpeakersChanged, remoteSpeakers);
      next.on(LivekitClient.RoomEvent.Reconnecting, () => { connected = false; release().catch(() => {}); remoteSpeakers(); $('voiceTalk').disabled = true; $('voiceStatus').textContent = 'Reconectando…'; $('connectionLight').classList.remove('connected'); });
      next.on(LivekitClient.RoomEvent.Reconnected, () => { connected = true; $('voiceTalk').disabled = false; $('connectionLight').classList.add('connected'); $('voiceStatus').textContent = muted ? 'Conectado · recepción silenciada' : 'Conectado · recepción activa'; resting(); });
      next.on(LivekitClient.RoomEvent.Disconnected, () => { if (room === next) leave().catch(() => {}); });
      await next.connect(access.serverUrl, access.participantToken); await next.startAudio(); connected = true;
      for (const id of ['voiceTalk','voiceMute','voiceLeave']) $(id).disabled = false;
      $('connectionLight').classList.add('connected'); $('voiceStatus').textContent = 'Conectado · recepción activa'; resting();
    } catch (e) { error(e.message); await leave(); }
    finally { connecting = false; }
  }
  async function press() {
    if (!connected || !room || claiming) return;
    held = true; claiming = true; $('voiceTalk').classList.add('held'); buttonState('PREPARANDO', 'Esperando el turno…');
    try {
      error(); const result = await api('claim', {}); lease = result.lease;
      if (!held || document.hidden) { await release(); return; }
      for (let i=0; i<30 && !room?.localParticipant.permissions?.canPublish; i++) {if (!held) break; await new Promise(resolve => setTimeout(resolve,100));}
      if (!held || document.hidden) { await release(); return; }
      if (!room?.localParticipant.permissions?.canPublish) throw new Error('Permiso de voz no confirmado. Intenta de nuevo.');
      await room.localParticipant.setMicrophoneEnabled(true);
      if (!held || document.hidden) { await release(); return; }
      buttonState('HABLANDO', 'Suelta para terminar'); $('microphoneState').textContent = 'Tu micrófono está transmitiendo'; $('microphoneState').classList.add('transmitting');
      timer = setTimeout(() => release().catch(() => {}), Math.max(0, result.expiresAt-Date.now()-1000));
    } catch (e) { error(e.message); await release().catch(() => {}); }
    finally { claiming = false; }
  }
  $('voiceTalk').onpointerdown = event => { if (!connected || event.button !== 0) return; event.preventDefault(); $('voiceTalk').setPointerCapture(event.pointerId); press(); };
  $('voiceTalk').onclick = () => { if (!connected && !connecting) join(); };
  for (const event of ['pointerup','pointercancel','lostpointercapture']) $('voiceTalk').addEventListener(event, () => release().catch(() => {}));
  $('voiceTalk').onkeydown = event => {if (connected && [' ','Enter'].includes(event.key) && !event.repeat) {event.preventDefault(); press();}};
  $('voiceTalk').onkeyup = event => {if ([' ','Enter'].includes(event.key)) release().catch(() => {});};
  window.addEventListener('blur', () => release().catch(() => {}));
  document.addEventListener('visibilitychange', () => {if (document.hidden) release().catch(() => {});});
  window.addEventListener('pagehide', () => leave().catch(() => {}));
  $('voiceJoin').onclick = join;
  $('voiceMute').onclick = () => { muted = !muted; $('voiceAudio').querySelectorAll('audio').forEach(element => element.muted = muted); $('voiceMute').textContent = muted ? 'Activar sonido' : 'Silenciar recepción'; $('voiceStatus').textContent = muted ? 'Conectado · recepción silenciada' : 'Conectado · recepción activa'; };
  $('voiceLeave').onclick = () => { $('voiceMenu').open = false; leave().catch(e => error(e.message)); };
  $('voiceMenu').addEventListener('toggle', () => { if ($('voiceMenu').open) release().catch(() => {}); });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') { $('voiceMenu').open = false; release().catch(() => {}); return; }
    const isM = event.key?.toLowerCase() === 'm';
    const editing = event.target?.isContentEditable || event.target?.closest?.('input,textarea,select,[contenteditable]');
    if (!isM || !connected || connecting || event.repeat || event.isComposing || event.ctrlKey || event.altKey || event.metaKey || editing || $('voiceMenu').open || keyboardHeld || claiming || held) return;
    event.preventDefault(); keyboardHeld = true; press();
  });
  document.addEventListener('keyup', event => {
    if ((event.key?.toLowerCase() === 'm' || event.code === 'KeyM') && keyboardHeld) {
      event.preventDefault(); release().catch(() => {});
    }
  });
  document.addEventListener('pointerdown', event => { if (!$('voiceMenu').contains(event.target)) $('voiceMenu').open = false; });
})();
