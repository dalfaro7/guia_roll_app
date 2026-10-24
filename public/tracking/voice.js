(() => {
  const $ = id => document.getElementById(id);
  let room = null, channel = null, connection = 0, turn = 0, held = false, claiming = false, lease = null, timer = null, muted = false;
  function presence(connected = false) {
    const identities = connected && room ? [room.localParticipant.identity, ...Array.from(room.remoteParticipants.values()).map(p=>p.identity)] : [];
    window.dispatchEvent(new CustomEvent('kayak-voice-presence',{detail:{channel, connected, identities}}));
  }
  const error = e => $('voiceError').textContent = e.message;
  function label(text) { $('voiceTalkLabel').textContent = text; }
  async function api(action, body, channelId) {
    const response = await fetch('/api/voice/' + action, {method: 'POST', headers: {'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content}, body:JSON.stringify({...body, channel_id:channelId}), signal:AbortSignal.timeout(8000)});
    const data = await response.json(); if (!response.ok) throw new Error(data.error || 'No se pudo conectar.'); return data;
  }
  async function release() {
    held = false; ++turn; clearTimeout(timer); $('voiceTalk').setAttribute('aria-pressed','false'); label('HABLAR');
    const previous = lease; lease = null; const current = room;
    try { await current?.localParticipant.setMicrophoneEnabled(false); }
    finally { if (previous) await api('release',{lease:previous.id},previous.channel).catch(error); }
  }
  async function disconnect() {
    const previous = room; room = null; presence();
    await release(); await previous?.localParticipant.setMicrophoneEnabled(false); await previous?.disconnect();
    $('voiceAudio').replaceChildren(); $('voiceTalk').disabled = true; $('voiceMute').disabled = true;
  }
  async function selectChannel() {
    const generation = ++connection, selected = $('voiceChannel').value;
    $('voiceChannel').disabled = true; $('voiceTalk').disabled = true; $('voiceError').textContent = '';
    let candidate;
    try {
      await disconnect(); channel = selected;
      if (!selected) { $('voiceStatus').textContent = 'Selecciona un canal'; return; }
      $('voiceStatus').textContent = 'Conectando al canal…';
      const access = await api('join',{},selected);
      if (generation !== connection) return;
      candidate = new LivekitClient.Room(); room = candidate;
      candidate.on(LivekitClient.RoomEvent.ParticipantConnected,()=>{if(room===candidate)presence(true);});
      candidate.on(LivekitClient.RoomEvent.ParticipantDisconnected,()=>{if(room===candidate)presence(true);});
      candidate.on(LivekitClient.RoomEvent.TrackSubscribed, track => {
        if (room !== candidate || track.kind !== 'audio') return;
        const element = track.attach(); element.autoplay = true; element.muted = muted; $('voiceAudio').append(element);
      });
      candidate.on(LivekitClient.RoomEvent.TrackUnsubscribed, track => track.detach().forEach(e=>e.remove()));
      candidate.on(LivekitClient.RoomEvent.ActiveSpeakersChanged, speakers => {
        if (room !== candidate) return;
        const others = speakers.filter(p=>p.identity !== candidate.localParticipant.identity);
        $('voiceStatus').textContent = others.length ? 'Habla: '+others.map(p=>p.name||'Participante').join(', ') : 'Conectado · micrófono apagado';
      });
      candidate.on(LivekitClient.RoomEvent.Reconnecting,()=>{ if(room===candidate){presence();release().catch(error);$('voiceTalk').disabled=true;$('voiceStatus').textContent='Reconectando…';} });
      candidate.on(LivekitClient.RoomEvent.Reconnected,()=>{if(room===candidate){presence(true);$('voiceTalk').disabled=false;$('voiceStatus').textContent='Conectado · micrófono apagado';}});
      candidate.on(LivekitClient.RoomEvent.Disconnected,()=>{if(room===candidate){presence();release().catch(error);room=null;$('voiceTalk').disabled=true;$('voiceMute').disabled=true;$('voiceChannel').value='';$('voiceStatus').textContent='Desconectado · selecciona un canal para reconectar';}});
      await candidate.connect(access.serverUrl,access.participantToken);
      if(generation!==connection){await candidate.disconnect();return;}
      presence(true);
      await candidate.startAudio();
      $('voiceTalk').disabled=false; $('voiceMute').disabled=false; $('voiceStatus').textContent='Conectado · micrófono apagado';
    } catch(e) {
      if(generation===connection){error(e);await disconnect().catch(()=>{});$('voiceChannel').value='';$('voiceStatus').textContent='No se pudo conectar · vuelve a seleccionar el canal';}
    } finally {if(generation===connection)$('voiceChannel').disabled=false;}
  }
  async function press() {
    if(!room||held||claiming||$('voiceTalk').disabled)return;
    held=true;claiming=true; const current=room, selected=channel, request=++turn;
    const valid=()=>held&&turn===request&&room===current;
    try {
      $('voiceError').textContent='';label('PREPARANDO');
      const result=await api('claim',{},selected);
      if(!valid()){await api('release',{lease:result.lease},selected);return;}
      lease={id:result.lease,channel:selected};
      for(let i=0;i<30&&!current.localParticipant.permissions?.canPublish&&valid();i++) await new Promise(r=>setTimeout(r,100));
      if(!valid())return;
      if(!current.localParticipant.permissions?.canPublish)throw new Error('Permiso de voz no confirmado.');
      await current.localParticipant.setMicrophoneEnabled(true);
      if(!valid()){await current.localParticipant.setMicrophoneEnabled(false);return;}
      $('voiceTalk').setAttribute('aria-pressed','true');label('HABLANDO');
      timer=setTimeout(()=>release().catch(error),Math.max(0,result.expiresAt-Date.now()-1000));
    } catch(e){error(e);if(turn===request)await release().catch(error);} finally {claiming=false;}
  }
  $('voiceChannel').onchange=selectChannel;
  $('voiceMute').onclick=()=>{muted=!muted;$('voiceAudio').querySelectorAll('audio').forEach(e=>e.muted=muted);$('voiceMute').textContent=muted?'Activar recepción':'Silenciar recepción';$('voiceMute').setAttribute('aria-pressed',String(muted));};
  $('voiceTalk').onpointerdown=e=>{if(e.button!==undefined&&e.button!==0)return;e.preventDefault();$('voiceTalk').setPointerCapture(e.pointerId);press();};
  for(const name of ['onpointerup','onpointercancel','onlostpointercapture'])$('voiceTalk')[name]=()=>release().catch(error);
  $('voiceTalk').onkeydown=e=>{if([' ','Enter'].includes(e.key)&&!e.repeat){e.preventDefault();press();}};
  $('voiceTalk').onkeyup=e=>{if([' ','Enter'].includes(e.key)){e.preventDefault();release().catch(error);}};
  document.addEventListener('keydown',e=>{if(e.code!=='KeyM'||e.repeat||e.isComposing||e.ctrlKey||e.altKey||e.metaKey||e.target.closest?.('input,textarea,select,[contenteditable]'))return;e.preventDefault();press();});
  document.addEventListener('keyup',e=>{if(e.code==='KeyM')release().catch(error);});
  window.addEventListener('blur',()=>release().catch(error));
  document.addEventListener('visibilitychange',()=>{if(document.hidden)release().catch(error);});
  window.addEventListener('pagehide',()=>{++connection;disconnect().catch(()=>{});});
})();
