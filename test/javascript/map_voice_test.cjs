const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const context={window:{}};
vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../../public/tracking/map-voice.js'),'utf8'),context);
const guideIds=context.window.KayakMapVoice.speakingGuideIds;
test('intercom identifies guide by session even when names match',()=>{
 const users=[{id:1,name:'Didier',voice_identities:['mobile-1','mobile-2']},{id:2,name:'Didier',voice_identities:['mobile-3']}];
 assert.deepEqual([...guideIds(users,['mobile-2'])],[1]);
 assert.deepEqual([...guideIds(users,['mobile-1','mobile-2'])],[1]);
 assert.deepEqual([...guideIds(users,['mobile-3'])],[2]);
});
test('silence, office participants and unknown identities do not light a guide marker',()=>{
 const users=[{id:1,voice_identities:['mobile-1']},{id:2}];
 assert.deepEqual([...guideIds(users,[])],[]);
 assert.deepEqual([...guideIds(users,['mobile-office','map-1-abc'])],[]);
});
