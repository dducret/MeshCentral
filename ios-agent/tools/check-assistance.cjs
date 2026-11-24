// SPDX-License-Identifier: Apache-2.0
'use strict';
// Run the actual shipped operator script with a deterministic DOM/WebSocket host.
// No browser rendering, Apple APIs or live account credentials are simulated as verified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { webcrypto, createHash } = require('node:crypto');
class Element {
    constructor() { this.children=[]; this.files=[]; this.value=''; this.textContent=''; this.width=360; this.height=640; }
    get options() { return this.children; }
    get firstElementChild() { return this.children[0]; }
    appendChild(child) { child.remove=()=>this.children.splice(this.children.indexOf(child),1); this.children.push(child); }
    replaceChildren() { this.children=[]; }
    getContext() { return {clearRect(){},drawImage(){},beginPath(){},moveTo(){},lineTo(){},stroke(){}}; }
    set innerHTML(_) { throw Error('Untrusted HTML rendering is forbidden'); }
    click() {} setPointerCapture() {}
    getBoundingClientRect() { return {left:0,top:0,width:360,height:640}; }
}
class Socket {
    static OPEN=1;
    static instances=[];
    constructor(url) { this.url=String(url); this.sent=[]; this.readyState=1; Socket.instances.push(this); }
    send(data) { this.sent.push(data); }
    close() { this.readyState=3; this.onclose?.(); }
}
const elements=new Map(), element=id=>{ if(!elements.has(id)) elements.set(id,new Element()); return elements.get(id); };
const context=vm.createContext({
    document:{getElementById:element,createElement:()=>new Element()}, location:new URL('https://example.invalid/team/ios-assist.html'),
    window:{addEventListener(){}}, URL, URLSearchParams, WebSocket:Socket, TextEncoder, Uint8Array, ArrayBuffer, DataView, Blob,
    crypto:webcrypto, performance, console, setTimeout:()=>1,clearTimeout(){},setInterval(){},
    btoa:text=>Buffer.from(text,'binary').toString('base64'),atob:text=>Buffer.from(text,'base64').toString('binary'),
    createImageBitmap:async()=>({width:720,height:1280,close(){}})
});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../operator/ios-console.js'),'utf8'),context,{timeout:2000});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../operator/ios-assist.js'),'utf8'),context,{timeout:2000});
const evaluate=code=>vm.runInContext(code,context,{timeout:2000});
const peer=value=>evaluate('message('+JSON.stringify({type:'iosAssist',v:1,...value})+')');
const get=expression=>JSON.parse(evaluate('JSON.stringify('+expression+')'));
const digest=data=>createHash('sha256').update(data).digest('hex');
const id='00000000-0000-4000-8000-000000000001';
(async()=>{
    const control=Socket.instances[0]; control.onopen();
    assert.equal(new URL(control.url).pathname,'/team/control.ashx');
    control.onmessage({data:JSON.stringify({action:'nodes',nodes:{mesh:[{_id:'node/team/synthetic',name:'iPhone test',conn:1,agent:{id:4294967280,caps:1,core:'MeshCentral iOS Rust 0.3.0 [broadcast-ready]'}}]}})});
    element('nodes').value='node/team/synthetic'; element('connect').onclick();
    assert.equal(JSON.parse(control.sent.at(-1)).action,'authcookie');
    control.onmessage({data:JSON.stringify({action:'authcookie',cookie:'test-cookie',rcookie:'test-relay-cookie'})});
    const relay=Socket.instances[1]; relay.onopen();
    assert.equal(element('sessionState').textContent,'Connexion au relais');
    const request=JSON.parse(control.sent.at(-1));
    assert.equal(request.usage,2); assert.match(request.value,/^\*\/team\/meshrelay\.ashx\?/);
    assert.equal(new URL(relay.url).searchParams.get('nodeid'),'node/team/synthetic');
    relay.onmessage({data:'c'}); assert.equal(relay.sent.at(-1),'2');
    await peer({action:'chat',text:'before consent'}); assert.equal(element('messages').children.length,0);
    await peer({action:'ready',chatAllowed:true,documentsAllowed:true});
    assert.equal(element('sessionState').textContent,'Assistance active');
    element('guidePlan').value='Ouvrez Réglages.';
    element('guideStart').onclick(); assert.equal(get('guide'),null); // Old agent: no false progress.
    await peer({action:'chat',text:'<img src=x onerror=alert(1)>'});
    assert.equal(element('messages').children[0].textContent,'iPhone : <img src=x onerror=alert(1)>');
    element('chat').value='Bonjour'; element('send').onclick();
    assert.equal(JSON.parse(relay.sent.at(-1)).text,'Bonjour');
    await assert.rejects(peer({action:'chat',text:'x'.repeat(1025)}));
    // Incoming document is not allocated or acknowledged before user acceptance.
    const bytes=Buffer.from(Array.from({length:9000},(_,i)=>i%256));
    const offer={action:'offer',id,name:'document.bin',size:bytes.length,kind:'document',sha256:digest(bytes)};
    const before=relay.sent.length; await peer(offer); assert.equal(relay.sent.length,before);
    assert.equal(get('incoming.bytes'),null);
    await assert.rejects(peer({action:'chunk',id,offset:0,data:'AA=='}));
    element('accept').onclick(); assert.equal(JSON.parse(relay.sent.at(-1)).offset,0);
    await assert.rejects(peer({action:'chunk',id,offset:1,data:'AA=='}));
    await peer({action:'chunk',id,offset:0,data:bytes.subarray(0,8192).toString('base64')});
    await peer({action:'chunk',id,offset:8192,data:bytes.subarray(8192).toString('base64')});
    assert.equal(get('received.offset'),9000);
    assert.equal(digest(Buffer.from(evaluate('received.bytes'))),digest(bytes));
    evaluate('received = null');
    // SHA mismatch and oversized/path-like resources are never exported.
    await assert.rejects(peer({...offer,name:'../private'}));
    await assert.rejects(peer({...offer,size:2*1024*1024+1}));
    await peer({...offer,size:1,sha256:'0'.repeat(64)}); element('accept').onclick();
    await assert.rejects(peer({action:'chunk',id,offset:0,data:'AA=='})); assert.equal(get('received'),null);
    // Outgoing document uses stop-and-wait, exact offsets and no duplicate progress.
    element('file').files=[{name:'out.bin',size:bytes.length,arrayBuffer:async()=>bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.length)}];
    await element('file').onchange();
    const outgoing=get('outgoing'); const startCount=relay.sent.length;
    assert.equal(JSON.parse(relay.sent.at(-1)).action,'offer');
    await peer({action:'ack',id:outgoing.id,offset:0}); assert.equal(relay.sent.length,startCount+1);
    assert.equal(element('outgoingProgress').value,0); // Sent bytes are not confirmed bytes.
    await peer({action:'ack',id:outgoing.id,offset:0}); assert.equal(relay.sent.length,startCount+1);
    await peer({action:'ack',id:outgoing.id,offset:8192});
    assert.equal(element('outgoingProgress').value,8192);
    assert.equal(Buffer.from(JSON.parse(relay.sent.at(-1)).data,'base64').length,808);
    await peer({action:'ack',id:outgoing.id,offset:9000}); assert.equal(get('outgoing'),null);
    assert.match(element('outgoingStatus').textContent,/Réception confirmée/);
    // Capture stays bound to its offer id; normalized stroke data is sent.
    const jpg=Buffer.from([255,216,255,217]);
    await peer({...offer,id,size:4,kind:'capture',sha256:digest(jpg)}); element('accept').onclick();
    await peer({action:'chunk',id,offset:0,data:jpg.toString('base64')});
    element('annotation').onpointerdown({pointerId:1,clientX:36,clientY:64});
    element('annotation').onpointermove({clientX:180,clientY:320});
    element('annotation').onpointerup(); element('annotate').onclick();
    const annotation=JSON.parse(relay.sent.at(-1));
    assert.equal(annotation.action,'annotations'); assert.equal(annotation.id,id);
    assert.deepEqual(annotation.strokes[0].points,[[0.1,0.1],[0.5,0.5]]);
    // Guided steps use feature negotiation, immutable illustration and local acknowledgments.
    await peer({action:'ready',chatAllowed:true,documentsAllowed:true,guidedAssistance:1});
    for(const plan of ['', 'a\n'.repeat(21), 'é'.repeat(401)]) {
        element('guidePlan').value=plan; element('guideStart').onclick(); assert.equal(get('guide'),null);
    }
    element('guidePlan').value='Ouvrez Réglages.\nTouchez Wi-Fi.';
    element('guideAttach').checked=true; element('guideStart').onclick();
    const step1=JSON.parse(relay.sent.at(-1));
    assert.equal(step1.action,'guideStep'); assert.equal(step1.step,1);
    assert.equal(step1.captureID,id); assert.deepEqual(step1.strokes,annotation.strokes);
    const guideID=step1.id, stepCount=relay.sent.length;
    element('guideNext').onclick(); assert.equal(relay.sent.length,stepCount);
    const reply=(step,status,other={})=>peer({action:'guideStatus',id:guideID,step,total:2,status,...other});
    await reply(1,'waiting'); assert.equal(get('guide.status'),'waiting');
    await reply(1,'done',{id:'00000000-0000-4000-8000-000000000002'});
    assert.equal(get('guide.status'),'waiting');
    await reply(1,'help'); element('guideNext').onclick(); assert.equal(relay.sent.length,stepCount);
    assert.match(element('guideStatus').textContent,/demande de l’aide/);
    await reply(1,'done'); assert.equal(element('guideNext').disabled,false);
    element('guideNextText').value='<b>Touchez Wi-Fi</b>'; element('guideNext').onclick();
    const step2=JSON.parse(relay.sent.at(-1)); assert.equal(step2.step,2); assert.equal(step2.captureID,undefined);
    await reply(1,'done'); assert.equal(get('guide.status'),'sending'); // Old response cannot complete step 2.
    await reply(2,'waiting'); await reply(2,'done');
    assert.match(element('guideStatus').textContent,/Parcours terminé/);
    assert.equal(element('guideSteps').children[1].textContent,'<b>Touchez Wi-Fi</b>');
    assert.equal(element('guideStart').disabled,false);
    // Device stop wins even while the next step is still in transit.
    element('guidePlan').value='Un\nDeux'; element('guideStart').onclick();
    const stoppedID=get('guide.id');
    await peer({action:'guideStatus',id:stoppedID,step:1,total:2,status:'done'});
    element('guideNext').onclick();
    await peer({action:'guideStatus',id:stoppedID,step:1,total:2,status:'stopped'});
    assert.equal(get('guide.status'),'stopped'); assert.equal(get('guide.pending'),null);
    // Expected stale capture error is recoverable without closing the screen/chat.
    element('guidePlan').value='Nouvelle étape'; element('guideAttach').checked=true; element('guideStart').onclick();
    const retryID=get('guide.id');
    await peer({action:'guideError',id:retryID,step:1,reason:'captureUnavailable'});
    assert.equal(get('ready'),true); assert.equal(get('guide.pending'),null); assert.equal(get('guide.status'),'idle');
    element('guideAttach').checked=false; element('guideNext').onclick();
    assert.equal(JSON.parse(relay.sent.at(-1)).step,1);
    element('guideStop').onclick(); assert.equal(get('guide.status'),'stopped');
    assert.equal(JSON.parse(relay.sent.at(-1)).action,'guideStop');
    await peer({action:'guideStatus',id:retryID,step:1,total:1,status:'waiting'});
    assert.equal(get('guide.status'),'stopped');
    await peer({action:'ready',chatAllowed:false,documentsAllowed:true,guidedAssistance:1});
    assert.equal(get('guideSupported'),false); assert.equal(element('guideStart').disabled,true);
    await peer({action:'diagnostics',fps:2,roundTripMS:20,kilobitsPerSecond:150,qualityLevel:1,token:'must-not-export'});
    assert.equal(get('metrics').token,undefined);
    await peer({action:'diagnostics',networkState:'available',networkInterface:'wifi',healthCode:2,frameAgeMS:9000,lowPower:true,osVersion:'injected-secret',fps:-1});
    assert.match(element('healthAdvice').textContent,/Aucune image/);
    assert.equal(get('metrics').osVersion,undefined); assert.equal(get('metrics.fps'),2);
    await peer({action:'diagnostics',remainingSeconds:500});assert.equal(get('metrics').remainingSeconds,undefined);
    await peer({action:'ready',chatAllowed:true,documentsAllowed:true,consoleVersion:1,sessionTiming:1,agentVersion:'0.4.0'});
    await peer({action:'diagnostics',remainingSeconds:123});assert.equal(get('metrics').remainingSeconds,123);
    assert.match(element('sessionTime').textContent,/2 min 3 s/);
    await peer({action:'diagnostics',remainingSeconds:601});assert.equal(get('metrics').remainingSeconds,undefined);
    // A JPEG decoding when the mask arrives cannot repaint on resume.
    evaluate('globalThis.decodeImage = createImageBitmap; globalThis.createImageBitmap = () => new Promise(resolve => { globalThis.finishDecode = resolve; })');
    const tile = 'new Uint8Array([0,3,0,12,0,0,0,0,255,216,255,217]).buffer';
    const oldFrame = evaluate('frame('+tile+')');
    const frameCount = get('metrics.frames');
    await peer({action:'screenVisibility',hidden:true});
    assert.equal(element('screen').hidden,true);
    assert.equal(element('capture').disabled,true);
    assert.match(element('streamFreshness').textContent,/Écran masqué/);
    const masked = relay.sent.length;
    element('capture').onclick();
    assert.equal(relay.sent.length,masked);
    await evaluate('frame('+tile+')');
    await peer({action:'chat',text:'Le chat continue.'});
    assert.equal(element('messages').children.at(-1).textContent,'iPhone : Le chat continue.');
    element('chat').value='Je vous entends'; element('send').onclick();
    assert.equal(JSON.parse(relay.sent.at(-1)).text,'Je vous entends');
    await peer({action:'screenVisibility',hidden:false});
    assert.equal(element('screen').hidden,false);
    assert.equal(element('capture').disabled,false);
    evaluate('finishDecode({width:720,height:1280,close(){}}); globalThis.createImageBitmap = decodeImage');
    await oldFrame;
    assert.equal(get('metrics.frames'),frameCount);
    await evaluate('frame('+tile+')');
    assert.equal(get('metrics.frames'),frameCount+1);
    element('file').files=[{name:'refused.bin',size:bytes.length,arrayBuffer:async()=>bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.length)}];
    await element('file').onchange();const refusedID=get('outgoing.id');
    await peer({action:'cancel',id:refusedID,reason:'rejected'});assert.match(element('outgoingStatus').textContent,/refusé/);
    element('reportNotes').value='Private note';
    const safe=get('consoleUI.exportReport(false)');
    assert.equal(safe.notes,undefined); assert(!JSON.stringify(safe).includes('Private note'));
    assert(safe.events.every(row=>row.text===undefined));
    const rich=get('consoleUI.exportReport(true)'); assert.equal(rich.notes,'Private note');
    assert(rich.events.some(row=>row.text?.includes('Bonjour')));
    let rejectLateRead;
    element('file').files=[{name:'late.bin',size:10,arrayBuffer:()=>new Promise((_,reject)=>{rejectLateRead=reject;})}];
    const lateRead=element('file').onchange();
    element('stop').onclick(); assert.equal(get('ready'),false); assert.equal(get('snapshotID'),null);
    const stoppedMessage=element('status').textContent;
    rejectLateRead(new Error('private file details'));await lateRead;
    assert.equal(element('status').textContent,stoppedMessage);assert.equal(element('outgoingStatus').textContent,'');
    assert.equal(element('messages').children.length,0); assert.equal(get('incoming'),null);
    assert.equal(get('guide'),null); assert.equal(element('guidePlan').value,'');
    assert.equal(element('outgoingProgress').hidden,true);assert.equal(element('incomingStatus').textContent,'');
    assert.match(element('streamFreshness').textContent,/inactive/);
    assert.equal(get('consoleUI.report.result'),'stopped');
    assert(get('consoleUI.report.endedAt'));
    element('reportClear').onclick(); assert.equal(get('consoleUI.report'),null);
    console.log('PASS: actual operator script: relay, consent, safe chat, transfers, annotated captures, guidance, screen masking and stale image rejection with live chat, diagnostics and disconnect cleanup.');
    console.log('Scope: deterministic DOM/WebSocket host; no actual browser rendering, live server relay or Apple code executed.');
})().catch(error=>{console.error(error);process.exitCode=1;});
