(() => {
  const labels={road_accident:'Accidente en la vía',controlled_traffic:'Tráfico regulado',road_closed:'Ruta Cerrada',police_checkpoint:'Control Policial',wildlife:'Vida silvestre',strainer:'Strainer',line_change:'Cambio en la línea',dangerous_rapid:'Rápido peligroso'};
  const animals={monkeys:'Monos',sloths:'Perezosos',other:'Otro animal'};
  const nodes=new Map();let running=false,timer,map;
  function expire(){for(const [id,n] of nodes){if(Date.parse(n.expiresAt)<=Date.now()){n.marker.remove();n.card.remove();nodes.delete(id);}}}

  const el=(tag,text)=>{const e=document.createElement(tag);if(text)e.textContent=text;return e;};
  const title=r=>labels[r.kind]+(r.animal?' · '+animals[r.animal]:'');
  async function json(url,options){const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),15000);try{const response=await fetch(url,{...options,signal:controller.signal});if(!response.ok)throw new Error(response.status===401?'Sesión finalizada.':'No se pudieron cargar los reportes.');return await response.json();}finally{clearTimeout(timeout);}}
  function card(r){
    const box=el('div');box.className='field-report-card';box.append(el('strong',title(r)),el('p',r.team+' · '+r.author),el('p',new Date(r.observed_at).toLocaleString('es-CR')),el('small','Se elimina a las '+new Date(r.expires_at).toLocaleTimeString('es-CR')));
    if(r.description)box.append(el('p',r.description));
    box.append(el('small','Precisión del punto: ±'+Math.round(r.accuracy)+' m'));
    const locate=el('button','Ver en mapa');locate.onclick=()=>{document.getElementById('fieldReportsDialog').close();document.getElementById('userSelect').value='';document.getElementById('search').value='';map.setView([r.latitude,r.longitude],16);nodes.get(r.id)?.marker.openPopup();};box.append(locate);
    const resolve=el('button','Marcar resuelto');resolve.onclick=async()=>{if(!confirm('¿Marcar este reporte como resuelto?'))return;resolve.disabled=true;try{await json('/api/field_reports/'+r.id+'/resolve',{method:'POST',headers:{'X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content}});await refresh();}catch(e){document.getElementById('fieldReportsStatus').textContent=e.message;resolve.disabled=false;}};box.append(resolve);return box;
  }
  async function refresh(){
    if(running)return;running=true;
    try{let rows=[],cursor=null;do{const result=await json('/api/field_reports'+(cursor?'?before='+cursor:''));rows.push(...result.items);cursor=result.next_before;}while(cursor);
      const keep=new Set(rows.map(r=>r.id));for(const [id,n] of nodes){if(!keep.has(id)){n.marker.remove();n.card.remove();nodes.delete(id);}}
      for(const r of rows){if(nodes.has(r.id))continue;const icon=el('span','⚑');icon.className='field-report-pin';icon.title=title(r);
        const marker=L.marker([r.latitude,r.longitude],{icon:L.divIcon({html:icon,className:'field-report-icon',iconSize:[28,32]}),title:title(r)}).addTo(map).bindPopup(card(r));
        const row=card(r);document.getElementById('fieldReportsList').append(row);nodes.set(r.id,{marker,card:row,expiresAt:r.expires_at});}
      document.getElementById('fieldReportsStatus').textContent=rows.length?rows.length+' reportes activos':'No hay reportes activos.';
    }catch(e){document.getElementById('fieldReportsStatus').textContent=e.message;}finally{running=false;}
  }
  window.KayakFieldReports={start(instance){if(timer)return;map=instance;document.getElementById('fieldReportsOpen').onclick=()=>{document.getElementById('fieldReportsDialog').showModal();refresh();};document.getElementById('fieldReportsClose').onclick=()=>document.getElementById('fieldReportsDialog').close();refresh();timer=setInterval(refresh,30000);setInterval(expire,1000);}};
})();
