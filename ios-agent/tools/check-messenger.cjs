// SPDX-License-Identifier: Apache-2.0
'use strict';
// Execute upstream UI/server snippets in bounded fixtures; no server or microphone is opened.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const fileSaver=fs.readFileSync(path.join(root,'public/scripts/filesaver.min.js'),'utf8').trim();
assert.equal(require('node:crypto').createHash('sha256').update(fileSaver).digest('hex'),
    'fc6fd8aa395cb265022e2789d5e0926c0aa9dee87370d9f22487047e399f51d4',
    'Re-audit the server FileSaver version/license before changing this reference');
const ui=fs.readFileSync(path.join(root,'views/default.handlebars'),'utf8');
const messenger=fs.readFileSync(path.join(root,'views/messenger.handlebars'),'utf8');
const server=fs.readFileSync(path.join(root,'meshuser.js'),'utf8');
function between(text,start,end){const a=text.indexOf(start);assert(a>=0,start);const b=text.indexOf(end,a+start.length);assert(b>a,end);return text.slice(a,b);}
const node='node/team/'+ 'A'.repeat(64), user='user/team/tech';
let opened, sent;
const browser=vm.createContext({xxdialogMode:false,currentNode:{_id:node,name:'Test iPad'},userinfo:{_id:user},
    serverinfo:{domainsuffix:'team'},authCookie:'fixture-only',features2:0,encodeURIComponentEx:encodeURIComponent,
    safeNewWindow:url=>opened=url,meshserver:{send:value=>sent=value}});
vm.runInContext(between(ui,'function deviceChat(e) {','function altDeviceChat(')+'\ndeviceChat({});',browser,{timeout:1000});
assert.equal(sent.action,'meshmessenger');assert.equal(sent.nodeid,node);
assert.equal(new URL(opened,'https://example.invalid').searchParams.get('id'),'meshmessenger/'+node+'/'+user);
// Execute both the real dispatcher and its actual local-agent routing function.
const branch=between(server,"case 'meshmessenger':","case 'createmesh':");
let routed;
let effectiveRights=0x4008;
const mesh='mesh/team/fixture';
const fixture=vm.createContext({command:sent,args:{port:443},domain:{id:'team'},user:{_id:user,name:'tech'},req:{},
    MESHRIGHT_CHATNOTIFY:0x4000,MESHRIGHT_REMOTECONTROL:8,MESHRIGHT_REMOTEVIEWONLY:0x100,MESHRIGHT_ADMIN:0xffffffff,
    common:require(path.join(root,'common.js')),encodeURIComponent,ws:{sessionId:'fixture-session'},
    parent:{getWebServerName:()=> 'example.invalid',GetNodeWithRights:(_d,_u,_n,cb)=>cb({_id:fixture.command.nodeid},effectiveRights,true),
        meshes:{[mesh]:{}},wsagents:{[node]:{dbNodeKey:node,dbMeshKey:mesh,send:value=>routed=JSON.parse(value)}}}});
vm.runInContext(between(server,'function routeCommandToNode(','function routeCommandToMesh('),fixture,{timeout:1000});
vm.runInContext('(function(){switch(command.action){'+branch+'}})()',fixture,{timeout:1000});
assert.equal(routed.action,'openUrl');assert.equal(routed.userid,user);assert.equal(routed.rights,0x4008);
assert.equal(routed.sessionid,'fixture-session');assert.equal(routed.nodeid,undefined);
const invite=new URL(routed.url);assert.equal(invite.origin,'https://example.invalid');assert.equal(invite.pathname,'/team/messenger');
assert.deepEqual([...invite.searchParams.keys()],['id']);assert.equal(invite.searchParams.get('id'),'meshmessenger/'+node+'/'+user);
for(const rights of [8,0x4000]) {
    routed=undefined;effectiveRights=rights;
    vm.runInContext('(function(){switch(command.action){'+branch+'}})()',fixture,{timeout:1000});assert.equal(routed,undefined);
}
// Default domain, encoded @/$ in node key, positive admin mask, empty real name.
const rootNode='node//@$'+'A'.repeat(62),rootUser='user//tech';
fixture.domain.id='';fixture.command={action:'meshmessenger',nodeid:rootNode};fixture.user={_id:rootUser,name:'tech',realname:''};
fixture.parent.wsagents={[rootNode]:{dbNodeKey:rootNode,dbMeshKey:mesh,send:value=>routed=JSON.parse(value)}};
effectiveRights=0xffffffff;
vm.runInContext('(function(){switch(command.action){'+branch+'}})()',fixture,{timeout:1000});
assert.equal(routed.rights,0xffffffff);assert.equal(routed.realname,'');assert.equal(routed.userid,rootUser);
const rootInvite=new URL(routed.url);assert.equal(rootInvite.pathname,'/messenger');
assert.deepEqual([...rootInvite.searchParams.keys()],['id']); // Operator title/auth never go to the device.
assert.equal(rootInvite.searchParams.get('id'),'meshmessenger/'+rootNode+'/'+rootUser);
routed=undefined;fixture.args.lanonly=true;
vm.runInContext('(function(){switch(command.action){'+branch+'}})()',fixture,{timeout:1000});assert.equal(routed,undefined);
// Real Messenger button logic: a microphone click requests audio only, never camera.
let constraints;
const media=vm.createContext({localStream:null,startLocalStream:value=>constraints=value});
vm.runInContext(between(messenger,'function micButtonClick() {','function hangUpButtonClick(')+'\nmicButtonClick();',media,{timeout:1000});
assert.equal(constraints.audio,true);assert.equal(constraints.video,false);
constraints=undefined;media.localStream={};vm.runInContext('micButtonClick();',media);assert.equal(constraints,undefined);
// Run the native action with both the separate and legacy shared media sessions.
const native=fs.readFileSync(path.join(__dirname,'../apple/App/Sources/AssistanceView.swift'),'utf8');
const nativeAction=/private static let microphoneScript = """([\s\S]*?)"""/.exec(native)[1];
const embedded=vm.createContext({window:{__meshIOSMedia:{approved:false}}});
assert.equal(vm.runInContext(nativeAction,embedded),'unsupported');
let requested=0;
embedded.micButtonClick=()=>{assert.equal(embedded.window.__meshIOSMedia.approved,true);requested++;embedded.localStream=1;};
assert.equal(vm.runInContext(nativeAction,embedded),'unsupported');
embedded.RTCPeerConnection=function(){};
assert.equal(vm.runInContext(nativeAction,embedded),'waiting');assert.equal(requested,0);
embedded.state=2;embedded.localStream=null;
assert.equal(vm.runInContext(nativeAction,embedded),'waiting');assert.equal(requested,0);
embedded.multiWebRtc=true;
assert.equal(vm.runInContext(nativeAction,embedded),'requested');assert.equal(requested,1);
assert.equal(embedded.window.__meshIOSMedia.approved,false);
assert.equal(vm.runInContext(nativeAction,embedded),'pending');assert.equal(requested,1);
embedded.state=0;assert.equal(vm.runInContext(nativeAction,embedded),'waiting');assert.equal(requested,1);
const controls={};const controlContext=vm.createContext({state:2,pushMessaging:false,webchannel:null,localStream:null,userMediaSupport:1,
    QE(){},QV:(id,value)=>controls[id]=!!value,updateLocalOutText(){}});
vm.runInContext(between(messenger,'function updateControls() {','// This is the WebRTC setup')+'\nupdateControls();',controlContext,{timeout:1000});
assert.equal(controls.micButton,false);controlContext.webchannel={ok:true};vm.runInContext('updateControls();',controlContext);
assert.equal(controls.micButton,true);controlContext.localStream={};vm.runInContext('updateControls();',controlContext);
assert.equal(controls.micButton,false);assert.equal(controls.hangupButton,true);
console.log('PASS: upstream Chat + actual agent route; named/default domains, encoded node key, admin/limited rights, empty real name, no operator token forwarding and LAN-only non-dispatch; audio-only/WebRTC controls. No rendered browser, Swift or media test.');
