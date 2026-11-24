// SPDX-License-Identifier: Apache-2.0
'use strict';
// Actual embedded scripts and upstream page functions. No browser/media claim.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'../..');
const native=fs.readFileSync(path.join(root,'ios-agent/apple/App/Sources/AssistanceView.swift'),'utf8');
const page=fs.readFileSync(process.argv[2]??path.join(root,'views/messenger.handlebars'),'utf8');
function script(name){const m=new RegExp('private static let '+name+' = """([\\s\\S]*?)"""').exec(native);assert(m,name);return m[1];}
function fn(name){const start=page.indexOf('        function '+name+'(');assert(start>=0,name);const end=page.indexOf('\n        function ',start+1);return page.slice(start,end);}
const sent=[],echo=[];
const styles=[];
let socket, relayStarts=0;
const input={value:'',focus(){throw Error('Native input must retain focus');}};
const elements={xouttext:input,xmsg:{},xmsgparent:{scrollTop:0,scrollHeight:10},localVideoCanvas:{removeAttribute(){}},remoteVideoCanvas:{removeAttribute(){}}};
const pageEvents={};
const context=vm.createContext({state:0,args:{id:'meshmessenger/node//'+ 'A'.repeat(64) +'/user//tech'},
    window:{location:{protocol:'https:',host:'example.invalid',pathname:'/messenger'},addEventListener:(name,handler)=>{pageEvents[name]=handler;}},
    document:{visibilityState:'visible',getElementById:id=>elements[id],createElement:()=>({}),head:{appendChild:style=>styles.push(style.textContent)}},
    navigator:{mediaDevices:{getUserMedia:()=>Promise.reject({name:'NotAllowedError'})}},TextEncoder,
    webchannel:null,localStream:null,multiWebRtc:true,webrtcSessions:{},RTCPeerConnection:function(){},DOMException,
    notificationSupport:false,notification:null,chatTextSession:'',pushMessaging:false,localOutText:false,
    serverRecording:false,random:0.5,Q:id=>elements[id],QV(){},QA:(_id,value)=>echo.push(value),
    EscapeHtml:s=>s.replace(/[&<>"']/g,c=>'&#'+c.charCodeAt(0)+';'),updateControls(){},displayControl(){},
    hangUpButtonClick(id){if(id===1){context.localStream=null;delete context.webrtcSessions[1];}},
    updateLocalOutText(){},updateRemoteOutText(){},displayLocalVideo(){},displayRemoteVideo(){},processMessage(){},
    disconnect(){context.state=0;},
    WebSocket:function(url){relayStarts++;this.url=url;this.readyState=1;this.bufferedAmount=0;this.send=value=>sent.push(JSON.parse(value));socket=this;}});
vm.runInContext(['sendws','send','displayRemote','xsend','start'].map(fn).join('\n'),context,{timeout:1000});
vm.runInContext('start()',context,{timeout:1000});
assert.equal(new URL(socket.url).searchParams.get('id'),context.args.id);
socket.onopen();assert.equal(context.state,1);
const send=new vm.Script('(function(message){'+script('sendScript')+'})(message)');
context.message='Bonjour';assert.equal(send.runInContext(context),'waiting');assert.equal(sent.length,0);
socket.onmessage({data:'c'});assert.equal(context.state,2);assert.equal(sent[0].action,'random');
const status=new vm.Script(script('stateScript'));
assert.equal(status.runInContext(context).ready,true);assert.equal(status.runInContext(context).state,2);
assert.equal(status.runInContext(context).data,false);
context.message='Bonjour "iPad" <script>danger()</script> \\ \n 😀';
assert.equal(send.runInContext(context),'sent');assert.equal(sent.at(-1).msg,context.message);
assert.equal(sent.at(-1).action,'chat');assert(echo.at(-1).includes('&#60;script&#62;'));assert.equal(input.value,'');
context.displayRemote('Écrivez <ici>\n'+'x'.repeat(140));
assert(echo.at(-1).includes('class="remoteBubble">Écrivez &#60;ici&#62;\n'+'x'.repeat(140)));
const before=sent.length;
for(const message of ['', '  ', 'a'.repeat(4097),'😀'.repeat(1025)]){
    context.message=message;assert.equal(send.runInContext(context),'invalid');assert.equal(sent.length,before);
}
context.message='a'.repeat(4096);assert.equal(send.runInContext(context),'sent');
socket.onclose();context.message='Ne pas rejouer';assert.equal(send.runInContext(context),'waiting');
context.state=2;context.webchannel={ok:true,readyState:'open',bufferedAmount:0,send:value=>sent.push(JSON.parse(value))};
assert.equal(status.runInContext(context).data,true);assert.equal(send.runInContext(context),'sent');
assert.equal(sent.at(-1).msg,'Ne pas rejouer');
context.webchannel.bufferedAmount=65537;assert.equal(send.runInContext(context),'waiting');
context.webchannel.bufferedAmount=0;context.webchannel.xoutBuffer=Array(16).fill('queued');assert.equal(send.runInContext(context),'waiting');
delete context.webchannel.xoutBuffer;context.webchannel.readyState='closing';assert.equal(send.runInContext(context),'waiting');
context.webchannel=null;socket.readyState=3;assert.equal(send.runInContext(context),'waiting');
socket.readyState=1;
let mediaRequests=0,constraints,resolveCapture,rejectCapture,restarts=0,mediaTracks=0,stoppedTracks=0;
context.navigator.mediaDevices.getUserMedia=value=>{
    mediaRequests++;constraints=value;
    return new Promise((resolve,reject)=>{resolveCapture=resolve;rejectCapture=reject;});
};
context.startWebRTC=id=>{
    assert.equal(id,1,'Media uses the upstream separate outbound session');
    return context.webrtcSessions[1]={iceConnectionState:'checking',addTrack(){mediaTracks++;},close(){this.iceConnectionState='closed';}};
};
context.webrtcSessions[0]={remoteDescription:{},signalingState:'stable',iceConnectionState:'checking',restartIce(){restarts++;}};
vm.runInContext([fn('startLocalStream'),fn('micButtonClick')].join('\n'),context,{timeout:1000});
vm.runInContext(script('pageScript'),context,{timeout:1000});
assert.equal(mediaRequests,0,'Loading the page must not activate media');
vm.runInContext('start()',context,{timeout:1000});
assert.equal(relayStarts,1,'A closed relay must not rejoin without a fresh invitation');
assert.equal(elements.remoteVideoCanvas.playsInline,true);
assert.match(styles[0], /#xmsg \.remoteBubble:not\(\[id\]\), #xmsg \.localBubble:not\(\[id\]\)/);
assert.match(styles[0], /font-size: var\(--mesh-ios-message-size, 24px\)/);
assert.match(styles[0], /overflow-wrap: anywhere/);
const poll=new vm.Script('(function(messageTextSize){'+script('messageTextSizeScript')+'\nreturn (\n'+script('stateScript')+'\n);})(messageTextSize)');
const transcript=elements.xmsgparent;
let cssSize='',styleWrites=0;
Object.assign(transcript,{scrollTop:240,scrollHeight:480,clientHeight:240,style:{
    getPropertyValue:name=>name==='--mesh-ios-message-size'?cssSize:'',
    setProperty(name,value){assert.equal(name,'--mesh-ios-message-size');cssSize=value;styleWrites++;transcript.scrollHeight+=120;},
}});
context.messageTextSize=72;
assert.equal(poll.runInContext(context).state,2,'Text sizing preserves the existing relay state poll');
assert.equal(cssSize,'72px');assert.equal(transcript.scrollTop,600,'Follow the latest message after resizing');
poll.runInContext(context);assert.equal(styleWrites,1,'Do not rewrite the style on every poll');
transcript.scrollTop=110;context.messageTextSize=28;
poll.runInContext(context);assert.equal(cssSize,'28px');assert.equal(transcript.scrollTop,110,'Do not jump to the bottom while reading earlier messages');
for(const invalid of [NaN, 0, 97, '24px; color:red']){
    context.messageTextSize=invalid;poll.runInContext(context);assert.equal(styleWrites,2);
}
const microphone=new vm.Script(script('microphoneScript'));
const turn=()=>new Promise(resolve=>setImmediate(resolve));
const audioTrack={readyState:'live',enabled:true,muted:false};
const stream={getTracks:()=>[{stop(){stoppedTracks++;}}],getAudioTracks:()=>[audioTrack]};
(async()=>{
    await assert.rejects(context.navigator.mediaDevices.getUserMedia({audio:true,video:false}));
    assert.equal(mediaRequests,0,'Capture needs the native button');
    assert.equal(status.runInContext(context).canStart,true);
    assert.equal(microphone.runInContext(context),'requested','Text relay alone allows the audio-only action');
    assert.equal(microphone.runInContext(context),'pending');
    assert.equal(mediaRequests,1);assert.equal(constraints.video,false);assert.equal(constraints.audio,true);
    assert.equal(status.runInContext(context).pending,true);
    rejectCapture({name:'NotAllowedError',message:'denied'});await turn();
    assert.equal(status.runInContext(context).error,1);assert.equal(context.localStream,null);assert.equal(restarts,0);

    assert.equal(microphone.runInContext(context),'requested');resolveCapture(stream);await turn();
    assert.equal(mediaRequests,2);assert.equal(restarts,1);assert.equal(mediaTracks,1);
    assert.equal(status.runInContext(context).error,0);assert.equal(status.runInContext(context).outbound,false);
    context.webrtcSessions[1].iceConnectionState='connected';
    assert.equal(status.runInContext(context).outbound,true);
    assert.equal(status.runInContext(context).duplex,false,'Outbound ICE is not enough for background audio');
    const remoteTrack={readyState:'live',enabled:true,muted:false};
    context.webrtcSessions[2]={iceConnectionState:'connected'};
    Object.assign(elements.remoteVideoCanvas,{paused:false,muted:false,srcObject:{getAudioTracks:()=>[remoteTrack]}});
    assert.equal(status.runInContext(context).duplex,true);
    assert.equal(status.runInContext(context).paired,true);
    context.navigator.audioSession={state:'interrupted'};
    assert.equal(status.runInContext(context).duplex,false,'WebKit can report an interruption before track state changes');
    assert.equal(status.runInContext(context).paired,true,'Media interruption does not close the relay');
    context.navigator.audioSession.state='active';
    elements.remoteVideoCanvas.paused=true;assert.equal(status.runInContext(context).duplex,false);
    elements.remoteVideoCanvas.paused=false;
    audioTrack.muted=true;assert.equal(status.runInContext(context).duplex,false);
    audioTrack.muted=false;
    remoteTrack.readyState='ended';assert.equal(status.runInContext(context).duplex,false);
    assert.equal(status.runInContext(context).data,false,'Voice peer status is distinct from the data channel');
    remoteTrack.readyState='live';
    assert.equal(microphone.runInContext(context),'active');
    let playbackAttempts=0;
    const player=elements.remoteVideoCanvas;
    player.paused=true;
    player.play=()=>{playbackAttempts++;return Promise.resolve();};
    const resume=new vm.Script('(() => { const restartCapture = forceRestart; return '+script('microphoneScript').trimStart()+' })()');
    context.forceRestart=false;
    context.document.visibilityState='hidden';
    assert.equal(resume.runInContext(context),'waiting');
    context.document.visibilityState='visible';
    const oldSocket=context.socket;
    context.socket={readyState:1};
    assert.equal(resume.runInContext(context),'closed','A replacement socket cannot inherit consent');
    assert.equal(status.runInContext(context).paired,false);
    context.socket=oldSocket;
    assert.equal(playbackAttempts,0);
    assert.equal(resume.runInContext(context),'active');
    assert.equal(playbackAttempts,1);
    assert.equal(mediaRequests,2,'Resume can reuse a surviving capture');

    const dataMessages=[];
    const dataChannel=context.webchannel={ok:true,readyState:'open',bufferedAmount:0,send:value=>dataMessages.push(JSON.parse(value))};
    context.message='Chat pendant la pause';
    assert.equal(send.runInContext(context),'sent');
    vm.runInContext(fn('hangUpButtonClick'),context,{timeout:1000});
    audioTrack.readyState='ended';
    const dataPeer=context.webrtcSessions[0], remotePeer=context.webrtcSessions[2];
    assert.equal(resume.runInContext(context),'requested');
    assert.deepEqual(sent.at(-1),{action:'videoStop',id:1});
    audioTrack.readyState='live';
    resolveCapture(stream);await turn();
    assert.equal(mediaTracks,2);
    assert.equal(context.webrtcSessions[0],dataPeer);
    assert.equal(context.webrtcSessions[2],remotePeer);
    assert.equal(context.webchannel,dataChannel);
    context.message='Même conversation après la reprise';
    assert.equal(send.runInContext(context),'sent');
    assert.deepEqual(dataMessages.map(value=>value.msg),['Chat pendant la pause','Même conversation après la reprise']);
    assert.equal(relayStarts,1);

    context.forceRestart=true;
    assert.equal(resume.runInContext(context),'requested');
    context.window.__meshIOSMedia.captureEpoch++;
    resolveCapture(stream);await turn();
    assert.equal(mediaTracks,2,'A cancelled resume must not start a new audio peer');
    assert.equal(stoppedTracks,3,'Obsolete tracks and the late capture are stopped');

    context.localStream=null;delete context.webrtcSessions[1];
    assert.equal(microphone.runInContext(context),'requested');resolveCapture(stream);await turn();
    assert.equal(restarts,1,'ICE only restarts once in this page');assert.equal(mediaTracks,3);
    context.localStream=null;delete context.webrtcSessions[1];
    assert.equal(microphone.runInContext(context),'requested');pageEvents.pagehide();
    resolveCapture(stream);await turn();
    assert.equal(stoppedTracks,4);assert.equal(mediaTracks,3,'A late capture must never start a peer after closing');
    context.window.__meshIOSMedia.error='untrusted detail';assert.equal(status.runInContext(context).error,0);
    // Rendering an ordinary non-Messenger HTML page cannot claim readiness.
    context.xsend=undefined;assert.equal(status.runInContext(context).ready,false);
    console.log('PASS: Messenger text transport and sizing, capture approval and late cleanup, media-only resume on the original relay, and preservation of the data and inbound peers. No rendered browser or Apple execution.');
})().catch(error=>{console.error(error);process.exitCode=1;});
