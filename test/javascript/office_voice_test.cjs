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
  const context={document:{hidden:false,getElementById:element,querySelector:()=>({content:'csrf-test'}),addEventListener:(name,fn)=>docEvents[name]=fn},window:{addEventListener:(name,fn)=>windowEvents[name]=fn},AbortController,setTimeout,clearTimeout,LivekitClient:{Room,RoomEvent:Object.fromEntries(['TrackSubscribed','TrackUnsubscribed','ActiveSpeakersChanged','Reconnecting','Reconnected','Disconnected'].map(name=>[name,name]))},fetch:async(url,options)=>{requests.push(url);bodies.push(options.body ? JSON.parse(options.body) : null);const data=url.endsWith('/join')?{serverUrl:'ws://test',participantToken:'test'}:url.endsWith('/claim')?await(claim?claim():{lease:'lease',expiresAt:Date.now()+30000}):{ok:true};return{ok:true,status:200,text:async()=>JSON.stringify(data)};}};
  vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../../public/tracking/office-voice.js'),'utf8'),context);
  return {element,mic,requests,bodies,docEvents,context,get room(){return room;},async connect(){element('voiceTalk').onclick();await flush();await flush();}};
}
test('large button connects without microphone, turns green while held, releases on focus loss',async()=>{
  const h=harness();await h.connect();
  assert.equal(h.element('talkLabel').textContent,'HABLAR');assert.equal(h.mic.includes(true),false);
  h.element('voiceTalk').onpointerdown({button:0,pointerId:1,preventDefault(){}});
  assert.equal(h.element('voiceTalk').classList.contains('held'),true);
  await flush();await flush();assert.equal(h.element('talkLabel').textContent,'HABLANDO');assert.equal(h.mic.at(-1),true);
  h.context.window;h.docEvents.visibilitychange;h.context.document.hidden=true;h.docEvents.visibilitychange();
  await flush();assert.equal(h.element('voiceTalk').classList.contains('held'),false);assert.equal(h.mic.at(-1),false);assert(h.requests.some(url=>url.endsWith('/release')));
});
test('releasing before the lease arrives never enables microphone',async()=>{
  let resolveClaim;const h=harness(()=>new Promise(resolve=>resolveClaim=resolve));await h.connect();
  h.element('voiceTalk').onpointerdown({button:0,pointerId:1,preventDefault(){}});await flush();
  h.element('voiceTalk').pointerup();resolveClaim({lease:'late',expiresAt:Date.now()+30000});await flush();await flush();
  assert.equal(h.mic.includes(true),false);assert(h.requests.some(url=>url.endsWith('/release')));assert.equal(h.element('voiceTalk').classList.contains('held'),false);
});
test('blue light only reports remote speakers and clears after they stop',async()=>{
  const h=harness();await h.connect();h.room.emit('ActiveSpeakersChanged',[{identity:'manuel',name:'Manuel'}]);
  assert.equal(h.element('remoteIndicator').classList.contains('speaking'),false);
  h.room.emit('ActiveSpeakersChanged',[{identity:'didier',name:'Didier'}]);assert.equal(h.element('remoteSpeaker').textContent,'Habla: Didier');assert.equal(h.element('remoteIndicator').classList.contains('speaking'),true);
  h.room.emit('ActiveSpeakersChanged',[]);assert.equal(h.element('remoteIndicator').classList.contains('speaking'),false);
});
test('holding M starts once, ignores repeats, and keyup releases the microphone',async()=>{
  const h=harness();await h.connect();
  const event={key:'m',code:'KeyM',target:{closest:()=>null},preventDefault(){}};
  h.docEvents.keydown(event);await flush();await flush();
  assert.equal(h.mic.at(-1),true);assert.equal(h.element('voiceTalk').classList.contains('held'),true);
  h.docEvents.keydown({...event,repeat:true});await flush();
  assert.equal(h.requests.filter(url=>url.endsWith('/claim')).length,1);
  h.docEvents.keyup({...event,key:'M'});await flush();
  assert.equal(h.mic.at(-1),false);assert.equal(h.element('voiceTalk').classList.contains('held'),false);
});
test('M does not activate while editing, using modifiers, or opening the menu',async()=>{
  const h=harness();await h.connect();const event={key:'m',target:{closest:()=>null},preventDefault(){}};
  for(const extra of [{ctrlKey:true},{altKey:true},{metaKey:true},{isComposing:true},{target:{isContentEditable:true}},{target:{closest:()=>({})}}])h.docEvents.keydown({...event,...extra});
  h.element('voiceMenu').open=true;h.docEvents.keydown(event);await flush();
  assert.equal(h.mic.includes(true),false);assert.equal(h.requests.filter(url=>url.endsWith('/claim')).length,0);
});

test('selected channel scopes join, claim and release; selector remains locked until disconnect',async()=>{
 const h=harness();h.element('voiceChannel').value='2';await h.connect();
 assert.equal(h.element('voiceChannel').disabled,true);
 h.element('voiceTalk').onpointerdown({button:0,pointerId:1,preventDefault(){}});await flush();await flush();
 h.element('voiceTalk').pointerup();await flush();await flush();
 assert.deepEqual(h.bodies.map(b=>b.channel_id),['2','2','2']);
 h.element('voiceLeave').onclick();await flush();await flush();
 assert.equal(h.element('voiceChannel').disabled,false);
});
test('unassigned account cannot connect or open its microphone',async()=>{
 const h=harness();h.element('voiceChannel').value='';await h.connect();
 assert.equal(h.requests.length,0);assert.equal(h.mic.includes(true),false);
 assert.match(h.element('voiceError').textContent,/asignarte un canal/);
});
