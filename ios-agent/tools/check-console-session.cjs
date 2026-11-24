// SPDX-License-Identifier: Apache-2.0
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
class Element {
    constructor(tag='div'){this.tag=tag;this.children=[];this.value='';this.files=[];this.width=360;this.height=640;}
    appendChild(child){this.children.push(child);if(this.tag==='select'&&this.children.length===1)this.value=child.value;}
    replaceChildren(){this.children=[];this.value='';}
    getContext(){return {clearRect(){},drawImage(){},beginPath(){},stroke(){}};}
    get options(){return this.children;}
    set innerHTML(_){throw Error('Unsafe HTML');}
}
function setup(fragment){
    const elements=new Map(),events={},sockets=[];
    const element=id=>{if(!elements.has(id))elements.set(id,new Element(id==='nodes'?'select':'div'));return elements.get(id);};
    class Socket{static OPEN=1;constructor(url){this.url=String(url);this.sent=[];this.readyState=1;sockets.push(this);}send(value){this.sent.push(value);}close(){this.readyState=3;this.onclose?.();}}
    const parent={},window={parent,addEventListener:(name,fn)=>events[name]=fn};
    const context=vm.createContext({document:{getElementById:element,createElement:tag=>new Element(tag)},window,location:new URL('https://example.invalid/team/ios-assist.html'+fragment),
        URL,URLSearchParams,TextEncoder,WebSocket:Socket,crypto:webcrypto,performance,console,setInterval(){},setTimeout(){return 1;},clearTimeout(){}});
    for(const file of ['ios-console.js','ios-assist.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../operator',file),'utf8'),context,{timeout:2000});
    const send=value=>sockets[0].onmessage({data:JSON.stringify(value)});
    sockets[0].onopen();
    return {element,events,sockets,send,parent,get:code=>vm.runInContext(code,context)};
}
const node=(id='a',caps=1)=>({_id:'node/team/'+id,name:'<img src=x>',conn:1,agent:{id:4294967280,caps,core:'MeshCentral iOS Rust 0.3.0 [broadcast-ready]'}});
const selected=setup('#node=node%2Fteam%2Fa&embedded=1');
selected.send({action:'nodes',nodes:{group:[null,node('b'),node('a',0)]}});
assert.equal(selected.element('nodes').children.length,1);assert.equal(selected.element('nodes').value,'node/team/a');assert(selected.element('connect').disabled);
assert(selected.element('deviceIdentity').textContent.includes('<img src=x>')); // text only
selected.send({action:'event',event:{action:'changenode',node:node()}});assert.equal(selected.element('connect').disabled,false);
selected.send({action:'event',event:{action:'changenode',node:{_id:'node/team/a',name:'Renamed'}}});assert.equal(selected.element('connect').disabled,false);
selected.element('connect').onclick();assert(selected.get('pairing'));
const message={data:{type:'meshcentral-ios-host',action:'leave'},source:selected.parent,origin:'https://evil.invalid'};
selected.events.message(message);assert(selected.get('pairing'));
selected.events.message({...message,origin:'https://example.invalid',source:{}});assert(selected.get('pairing'));
selected.events.message({...message,origin:'https://example.invalid'});assert(!selected.get('pairing'));assert.equal(selected.get('consoleUI.report.result'),'page_left');
selected.element('connect').onclick();selected.send({action:'authcookie',cookie:'test',rcookie:'test-relay'});
assert.equal(new URL(selected.sockets[1].url).searchParams.get('nodeid'),'node/team/a');
selected.send({action:'event',event:{action:'nodeconnect',nodeid:'node/team/a',conn:0}});
assert.equal(selected.sockets[1].readyState,3);assert(!selected.get('pairing'));assert(selected.element('connect').disabled);
const missing=setup('#node=node%2Fteam%2Funknown');missing.send({action:'nodes',nodes:{group:[node()]}});missing.element('connect').onclick();assert(!missing.get('pairing'));assert.equal(missing.element('nodes').children.length,0);
const standalone=setup('');standalone.send({action:'nodes',nodes:{group:[node()]}});assert.equal(standalone.element('connect').disabled,false);
standalone.element('connect').onclick();standalone.send({action:'event',event:{action:'removenode',nodeid:'node/team/a'}});assert(!standalone.get('pairing'));
standalone.send(null);standalone.send([]);standalone.send(42);assert(!standalone.get('pairing'));
selected.send({action:'event',event:{action:'nodeconnect',nodeid:'node/team/a',conn:1}});
selected.element('connect').onclick();selected.send({action:'authcookie',cookie:'test2',rcookie:'test-relay2'});
selected.sockets[2].onmessage({data:'null'});assert(!selected.get('pairing'));assert.equal(selected.get('consoleUI.report.result'),'invalid_data');
console.log('PASS: authorized fragment preselection, no fallback to other device, capability/presence updates, parent origin/source checks, offline and access-removal cleanup.');
