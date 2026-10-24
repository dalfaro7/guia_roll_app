(() => {
  function speakingGuideIds(users, identities) {
    const speaking = new Set(identities);
    return new Set(users.filter(user => (user.voice_identities || []).some(identity => speaking.has(identity))).map(user => user.id));
  }
  function start(onSpeakers, onStatus) {
    let stopped = false, retry = null, controller = null, expiry = null;
    async function refresh() {
      if (stopped) return;
      controller = new AbortController();
      const timeout = setTimeout(() => controller?.abort(), 4000);
      try {
        const channel = document.getElementById('voiceChannel').value;
        const response = await fetch('/api/map/voice?channel_id=' + encodeURIComponent(channel), {signal:controller.signal,cache:'no-store'});
        if (!response.ok) {if ([401,403].includes(response.status)) stopped = true;throw new Error('Unavailable');}
        const data = await response.json(); if (stopped || channel !== document.getElementById('voiceChannel').value) return;
        clearTimeout(expiry);
        const speakers = (data.speakers || []).filter(speaker => speaker.expiresAt > Date.now());
        onSpeakers(speakers.map(speaker => speaker.identity));
        if (speakers.length) expiry = setTimeout(() => onSpeakers([]), Math.max(0,Math.min(...speakers.map(speaker => speaker.expiresAt))-Date.now()));
        onStatus('Intercomunicador · turno de voz en vivo');
      } catch {clearTimeout(expiry);onSpeakers([]);onStatus('Indicador de voz no disponible');}
      finally {clearTimeout(timeout);if (!stopped) retry = setTimeout(refresh,750);}
    }
    function stop() {stopped=true;clearTimeout(retry);clearTimeout(expiry);controller?.abort();onSpeakers([]);}
    window.addEventListener('pagehide',stop,{once:true});refresh();return stop;
  }
  window.KayakMapVoice = {speakingGuideIds,start};
})();
