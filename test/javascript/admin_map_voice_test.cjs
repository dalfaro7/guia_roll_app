const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {EventEmitter}=require('node:events');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function harness(claim) {
  const nodes=new Map(), mic=[], requests=[], bodies=[], docEvents={}, windowEvents={};
  const element=id=>{if(!nodes.has(id)){const classes=new Set();nodes.set(id,{id,value:id==='voiceChannel'?'1':'',selectedOptions:[{textContent:'Arenal Rafting Team'}],textContent:'',hidden:false,disabled:false,open:false,classList:{add:x=>classes.add(x),remove:x=>classes.delete(x),contains:x=>classes.has(x),toggle:(x,v)=>v?classes.add(x):classes.delete(x)},setAttribute(k,v){this[k]=v;},addEventListener(k,fn){this[k]=fn;},querySelectorAll(){return[];},replaceChildren(){},contains(){return false;},setPointerCapture(){}});}return nodes.get(id);};
  let room;
  class Room extends EventEmitter {constructor(){super();room=this;this.localParticipant={identity:'manuel',permissions:{canPublish:true},setMicrophoneEnabled:async value=>{mic.push(value);}};}async connect(){}async startAudio(){}async disconnect(){this.emit('Disconnected');}}
  const context={document:{hidden:false,getElementById:element,querySelector:()=>({content:'csrf-test'}),addEventListener:(name,fn)=>docEvents[name]=fn},window:{addEventListener:(name,fn)=>windowEvents[name]=fn},AbortController,AbortSignal,setTimeout,clearTimeout,LivekitClient:{Room,RoomEvent:Object.fromEntries(['TrackSubscribed','TrackUnsubscribed','ActiveSpeakersChanged','Reconnecting','Reconnected','Disconnected'].map(name=>[name,name]))},fetch:async(url,options)=>{requests.push(url);bodies.push(options.body ? JSON.parse(options.body) : null);const data=url.endsWith('/join')?{serverUrl:'ws://test',participantToken:'test'}:url.endsWith('/claim')?await(claim?claim():{lease:'lease',expiresAt:Date.now()+30000}):{ok:true};return{ok:true,status:200,json:async()=>data};}};
  vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../../public/tracking/voice.js'),'utf8'),context);
  return {element,mic,requests,bodies,docEvents,context,get room(){return room;},async connect(){await element('voiceChannel').onchange();await flush();await flush();}};
}
test('admin M transmits on selected channel and releases on blur',async()=>{
 const h=harness();h.element('voiceChannel').value='2';await h.connect();
 assert.equal(h.mic.includes(true),false);
 const event={code:'KeyM',target:{closest:()=>null},preventDefault(){}};
 h.docEvents.keydown(event);await flush();await flush();
 assert.equal(h.mic.at(-1),true);assert.equal(h.element('voiceTalk')['aria-pressed'],'true');
 h.docEvents.keydown({...event,repeat:true});await flush();
 assert.equal(h.requests.filter(x=>x.endsWith('/claim')).length,1);
 h.docEvents.keyup(event);await flush();await flush();
 assert.equal(h.mic.at(-1),false);assert.equal(h.element('voiceTalk')['aria-pressed'],'false');
 assert.deepEqual(h.bodies.map(b=>b.channel_id),['2','2','2']);
});
test('typing M in fields does not transmit and late grants after release stay silent',async()=>{
 let resolveClaim;const h=harness(()=>new Promise(resolve=>resolveClaim=resolve));await h.connect();
 const event={code:'KeyM',target:{closest:()=>({})},preventDefault(){}};
 h.docEvents.keydown(event);assert.equal(h.requests.filter(x=>x.endsWith('/claim')).length,0);
 h.docEvents.keydown({...event,target:{closest:()=>null}});await flush();
 h.docEvents.keyup(event);resolveClaim({lease:'late',expiresAt:Date.now()+30000});await flush();await flush();
 assert.equal(h.mic.includes(true),false);assert(h.requests.some(x=>x.endsWith('/release')));
});

test('channel selection connects immediately and one reception button toggles both ways',async()=>{
 const h=harness();await h.connect();assert.equal(h.requests.filter(x=>x.endsWith('/join')).length,1);
 h.element('voiceMute').onclick();assert.equal(h.element('voiceMute').textContent,'Activar recepción');
 h.element('voiceMute').onclick();assert.equal(h.element('voiceMute').textContent,'Silenciar recepción');
 h.element('voiceChannel').value='2';await h.connect();assert.equal(h.bodies.at(-1).channel_id,'2');assert.equal(h.element('voiceTalk').disabled,false);
});
test('switching channel with a pending claim releases the old channel without transmitting',async()=>{
 let resolveClaim;const h=harness(()=>new Promise(resolve=>resolveClaim=resolve));await h.connect();
 h.docEvents.keydown({code:'KeyM',target:{closest:()=>null},preventDefault(){}});await flush();
 h.element('voiceChannel').value='2';await h.connect();
 resolveClaim({lease:'old',expiresAt:Date.now()+30000});await flush();await flush();
 assert.equal(h.mic.includes(true),false);const releaseIndex=h.requests.findIndex(x=>x.endsWith('/release'));
 assert.equal(h.bodies[releaseIndex].channel_id,'1');assert.equal(h.bodies[releaseIndex].lease,'old');
});
