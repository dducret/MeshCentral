// SPDX-License-Identifier: Apache-2.0
'use strict';
// Real upstream handler/Details code in isolated JS contexts, not a browser render.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {execFileSync}=require('node:child_process'),{createHash}=require('node:crypto');
const root=path.resolve(__dirname,'../..'),agentRoot=path.join(root,'ios-agent');
const ui=fs.readFileSync(path.join(root,'views/default.handlebars'),'utf8');
const agent=fs.readFileSync(path.join(root,'meshagent.js'),'utf8');
const user=fs.readFileSync(path.join(root,'meshuser.js'),'utf8');
const common=require(path.join(root,'common.js'));
function between(text,start,end){const a=text.indexOf(start),b=text.indexOf(end,a+start.length);assert(a>=0&&b>a,start);return text.slice(a,b);}
const fixtures=Object.fromEntries(execFileSync('cargo',['run','--offline','--locked','--quiet','--example','inventory_fixtures'],
    {cwd:agentRoot,encoding:'utf8'}).trim().split(/\r?\n/).map(line=>{const [name,json]=line.split('\t');return [name,{body:json,data:JSON.parse(json)}];}));
const nodeid='node/test/'+ 'A'.repeat(64),meshid='mesh/test/'+ 'B'.repeat(64);
let stored,notification,reply,rights=0x100008,visible=true;
const clone=value=>JSON.parse(JSON.stringify(value));
const context=vm.createContext({command:null,common,domain:{id:'test'},user:{},MESHRIGHT_DEVICEDETAILS:0x100000,MESHRIGHT_ADMIN:0xffffffff,
    validNodeIdAndDomain:c=>c.nodeid===nodeid,
    obj:{dbNodeKey:nodeid,dbMeshKey:meshid,send:value=>reply=typeof value==='string'?JSON.parse(value):clone(value)},
    db:{Set:value=>stored=clone(value),Get:(_key,cb)=>cb(null,stored?[clone(stored)]:[]),GetHash:(_key,cb)=>cb(null,stored?[{hash:stored.hash}]:[])},
    parent:{CreateMeshDispatchTargets:()=>[meshid,nodeid],parent:{DispatchEvent:(_targets,_agent,event)=>notification=event},
        GetNodeWithRights:(_d,_u,_n,cb)=>cb({_id:nodeid},rights,visible)}});
const branches=between(agent,"case 'sysinfo': {","case 'sessions': {");
function command(value){context.command=value;vm.runInContext('(function(){switch(command.action){'+branches+'}})()',context,{timeout:1000});}
command({action:'sysinfocheck'});assert.equal(reply.action,'sysinfo');assert.equal(reply.hash,undefined);
const getInfo=user.slice(user.indexOf('function serverCommandGetSysInfo(command) {')).split('\n    function ')[0];
vm.runInContext(getInfo,context,{timeout:1000});
let html='';
const currentNode={_id:nodeid,osdesc:'iPadOS fixture',agent:{id:0xfffffff0,ver:4,caps:1},conn:1};
const browser=vm.createContext({currentNode,DeviceDetailsHardware:null,DeviceDetailsNetwork:null,DeviceDetailsNodeId:null,
    agentsStr:{},printDateTime:value=>value.toISOString(),EscapeHtml:value=>String(value).replace(/[&<>"']/g,c=>'&#'+c.charCodeAt(0)+';'),
    addDetailItem:(label,value)=>`<div>${label}: ${value}</div>`,format:(str,...args)=>str.replace(/\{(\d+)\}/g,(_m,i)=>args[i]),
    QH:(id,value)=>{assert.equal(id,'p17info2');html=value;}});
vm.runInContext(between(ui,'function updateDeviceDetails(node, hardware, network) {','function deviceDetailsShowBitlockerInfo('),browser,{timeout:1000});
for(const [name,fixture] of Object.entries(fixtures)){
    const hash=createHash('sha384').update(fixture.body).digest('hex');
    command({action:'sysinfo',data:{...clone(fixture.data),hash}});
    assert.equal(stored._id,'si'+nodeid);assert.equal(stored.hash,hash);assert.equal(stored.domain,'test');assert.equal(stored.type,'sysinfo');assert(stored.time>0);
    assert.equal(notification.action,'sysinfohash');assert.equal(notification.nodeid,nodeid);
    command({action:'sysinfocheck'});assert.equal(reply.hash,hash);
    context.command={action:'getsysinfo',nodeid};vm.runInContext('serverCommandGetSysInfo(command)',context,{timeout:1000});
    assert.equal(reply.action,'getsysinfo');assert.equal(reply._id,undefined);assert.equal(reply.domain,undefined);
    browser.hardware={...reply.hardware,time:reply.time};
    vm.runInContext('updateDeviceDetails(currentNode, hardware, null)',browser,{timeout:1000});
    assert(html.includes('iPadOS fixture'));assert(html.includes('Apple'));assert(html.includes('arm64'));
    if(name==='simulator') {assert(html.includes('iPad Simulator'));assert(!html.includes('8192'));assert(!html.includes('Battery Charge'));}
    else {assert(html.includes('iPad14,3'));assert(html.includes('8192 MiB'));assert(html.includes('8 processing cores'));}
    if(name==='device') assert(html.includes('0 %'), 'A numeric zero would disappear in the upstream truthiness test');
    if(name==='unknown') assert(!html.includes('Battery Charge'));
    if(name==='charging') {assert(html.includes('71 %'));assert(html.includes('Charging: Yes'));}
    if(name==='full') {assert(html.includes('100 %'));assert(html.includes('Charging: No'));}
    assert(!html.includes('Storage Volumes'));assert(!html.includes('Serial:'));assert(!html.includes('Identifier:'));
}
rights=8;vm.runInContext('serverCommandGetSysInfo(command)',context,{timeout:1000});assert.equal(reply.noinfo,true);assert.equal(reply.hardware,undefined);
rights=0x100008;visible=false;vm.runInContext('serverCommandGetSysInfo(command)',context,{timeout:1000});assert.equal(reply.noinfo,true);
const old=clone(stored);command({action:'sysinfo',data:{hardware:{},hash:'x',bad:{$bad:'key'}}});assert.deepEqual(stored,old);
let refresh;
const refreshContext=vm.createContext({currentNode,xxdialogMode:false,meshserver:{send:cmd=>refresh=cmd}});
vm.runInContext(between(ui,'function refreshDetails() {','function deviceDetailsStatsClear('),refreshContext,{timeout:1000});
vm.runInContext('refreshDetails()',refreshContext,{timeout:1000});assert.equal(refresh.type,'sysinfo');assert.equal(refresh.nodeid,nodeid);
console.log('PASS: 5 Rust inventories -> actual upstream sysinfo storage/hash events -> rights-filtered getsysinfo -> Details HTML generation; zero/unknown battery, simulator, and invalid Mongo fields. No rendered browser/device test.');
