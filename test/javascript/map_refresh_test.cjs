const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
function harness() {
  const all = [];
  class Element {
    constructor(tag) { this.tag = tag; this.children = []; this.dataset = {}; this.value = ''; this.textContent = ''; this.className = ''; this.classList = {toggle: () => {}}; all.push(this); }
    append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
    insertBefore(node, before) { node.parent = this; this.children.splice(this.children.indexOf(before), 0, node); }
    remove() { if (this.parent) this.parent.children = this.parent.children.filter(n => n !== this); this.removed = true; }
    querySelector(selector) { return this.children.find(n => selector.startsWith('.') ? n.className.split(' ').includes(selector.slice(1)) : n.tag === selector); }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    setAttribute() {}
    closest() { return null; }
  }
  const nodes = new Map();
  const element = id => { if (!nodes.has(id)) nodes.set(id, new Element('div')); return nodes.get(id); };
  const views = [], created = [];
  const context = vm.createContext({console, Date, Set, Map, setInterval, clearInterval, location: {}, window: {},
    document: { getElementById: element, createElement: tag => new Element(tag), createTextNode: value => ({nodeValue:value}), querySelectorAll: () => [], querySelector: () => ({content:'csrf'}) },
    L: {divIcon: o => o, marker: (coords, options) => { const marker = {options, coords, updates:0, addTo(){return this;}, getLatLng(){return {lat:this.coords[0],lng:this.coords[1]};}, setLatLng(c){this.coords=c;this.updates++;}, getElement(){return options.icon.html;}, remove(){this.removed=true;}};created.push(marker);return marker;}},
    fetch: async () => {throw new Error('Unexpected request');}
  });
  const source = fs.readFileSync(path.join(__dirname,'../../public/tracking/app.js'),'utf8').replace(/api\('me'\)\.then\(openDashboard\)[\s\S]*$/, '');
  vm.runInContext(source, context);
  context.testMap = {setView:(...args)=>views.push(args)};
  vm.runInContext('map = testMap',context);
  return {context, element, created, views, run:code=>vm.runInContext(code,context)};
}
const user = () => ({id:1,name:'Test user',latitude:10,longitude:-84,captured_at:Date.now(),accuracy:5,speed_kmh:0,speed_estimate:{status:'warming_up',samples:3}});
test('refresh keeps user controls and marker identity, moves marker and focuses latest coordinates only on click',()=>{
  const h=harness();h.context.next=[user()];h.run('users=next;render()');
  const button=h.element('users').children[0], marker=h.created[0];
  button.disabled=true;
  h.context.next=[{...user(),latitude:10.1,name:'Updated user'}];h.run('users=next;render()');
  assert.equal(h.element('users').children[0],button);assert.equal(button.disabled,true);
  assert.equal(h.created.length,1);assert.equal(marker.updates,1);assert.equal(h.views.length,0);
  button.onclick();assert.equal(h.views[0][0][0],10.1);
  h.element('search').value='unmatched';h.run('render()');assert.equal(button.hidden,true);assert.equal(h.created.length,1);
  h.run('users=[];render()');assert.equal(marker.removed,true);assert.equal(button.removed,true);
});
test('speed shows zero GPS honestly during warmup, unavailable for missing GPS, and estimated speed when ready',()=>{
  const h=harness();h.context.u=user();
  assert.match(h.run('speedDisplay(u).value'),/GPS: 0 km\/h/);
  h.context.u.speed_kmh=null;assert.equal(h.run('speedDisplay(u).value'),'Velocidad no disponible');
  h.context.u.speed_estimate={status:'ready',kmh:12,endpoints_kmh:10,segments_kmh:14,samples:11};
  assert.equal(h.run('speedDisplay(u).value'),'Estimada: 12 km/h');
  h.context.u.captured_at=Date.now()-190000;assert.equal(h.run('speedDisplay(u).value'),'Estimada: 12 km/h');
  h.context.u.speed_estimate={status:'warming_up',last_valid:{kmh:7,calculated_at:Date.now()-120000}};
  assert.equal(h.run('speedDisplay(u).value'),'Estimada: 7 km/h');
  h.context.u.speed_estimate.last_valid.calculated_at=Date.now()-301000;
  assert.equal(h.run('speedDisplay(u).value'),'Velocidad no disponible');
});
test('overlapping dashboard refreshes share one request and never restart voice',async()=>{
  const h=harness();let finish,calls=0;h.context.fetch=()=>{calls++;return new Promise(resolve=>finish=resolve);};
  const first=h.run('refresh()');await h.run('refresh()');assert.equal(calls,1);
  finish({ok:true,json:async()=>[user()]});await first;assert.equal(h.created.length,1);
});
test('alert refresh retains disabled acknowledgement button',async()=>{
  const h=harness();h.context.fetch=async()=>({ok:true,json:async()=>({unreadCount:1,items:[{id:3,user_name:'Test',peak_kmh:95,first_at:Date.now()}]})});
  await h.run('refreshAlerts()');const row=h.element('speedAlerts').children[1],button=row.children[1];button.disabled=true;
  await h.run('refreshAlerts()');assert.equal(h.element('speedAlerts').children[1],row);assert.equal(row.children[1],button);assert.equal(button.disabled,true);
});
test('late report response cannot overwrite newly selected date',async()=>{
  const h=harness();let finish;h.element('reportDialog').open=true;h.element('reportDate').value='2026-10-23';
  h.context.fetch=()=>new Promise(resolve=>finish=resolve);const pending=h.run('loadReport()');
  h.element('reportDate').value='2026-10-24';finish({ok:true,json:async()=>({day:'2026-10-23',items:[]})});await pending;
  assert.equal(h.element('reportDate').value,'2026-10-24');assert.equal(h.element('reportSummary').textContent,'');
});

test('orange warning uses a recent estimated average strictly above 90, never GPS alone',()=>{
  const h=harness();h.context.u={...user(),speed_kmh:110};
  assert.notEqual(h.run('speedDisplay(u).overLimit'),true);
  h.context.u.speed_estimate={status:'ready',kmh:90,calculated_at:Date.now()};
  assert.equal(h.run('speedDisplay(u).overLimit'),false);
  h.context.u.speed_estimate.kmh=90.1;assert.equal(h.run('speedDisplay(u).overLimit'),true);
  h.context.u.speed_estimate.calculated_at=Date.now()-301000;assert.notEqual(h.run('speedDisplay(u).overLimit'),true);
});
