// SPDX-License-Identifier: Apache-2.0
'use strict';
// Exercise the shipped plugin through this checkout's actual export serializer.
const assert=require('node:assert/strict'),path=require('node:path'),vm=require('node:vm');
const handler=require('../../pluginHandler.js').pluginHandler({path,datapath:__dirname,config:{settings:{plugins:{list:[]}}}});
handler.plugins.iosAssistance=require('../plugin/iosAssistance/iosAssistance.js').iosAssistance();
handler.exports.iosAssistance=handler.plugins.iosAssistance.exports;
class Element {
    constructor(tag='div') { this.tagName=tag;this.children=[];this.style={};this.classes=new Set();this.classList={contains:s=>this.classes.has(s),add:s=>this.classes.add(s),remove:s=>this.classes.delete(s)};this.messages=[];this.contentWindow={postMessage:(...args)=>this.messages.push(args)}; }
    appendChild(child){child.parent=this;this.children.push(child);return child;}
    remove(){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);}
    set innerHTML(value){this.children=[];for(const match of value.matchAll(/<(span|div)\b([^>]+)>/g)){const item=new Element(match[1]);item.id=/id="([^"]+)"/.exec(match[2])?.[1];if(match[2].includes('class="on"'))item.classes.add('on');this.appendChild(item);}}
    get innerHTML(){return this.children.map(c=>`<${c.tagName} id="${c.id}"${c.classes.has('on')?' class="on"':''}></${c.tagName}>`).join('');}
    querySelectorAll(selector){return this.children.filter(c=>selector==='span.on'?c.tagName==='span'&&c.classes.has('on'):selector==='span'?c.tagName==='span':c.tagName==='div');}
}
const root=new Element(),make=(id,parent=root)=>{const element=new Element();element.id=id;parent.appendChild(element);return element;};
const page=make('p19'),headers=make('p19headers',page),pages=make('p19pages',page);make('MainDevPlugins');
function find(id,element=root){if(element.id===id)return element;for(const child of element.children){const found=find(id,child);if(found)return found;}return null;}
const context=vm.createContext({document:{getElementById:find,createElement:tag=>new Element(tag)},URL,URLSearchParams,location:new URL('https://example.invalid/team/?view=19'),
    MutationObserver:class{observe(){}},xxcurrentView:19,currentNode:null,putstore(){}});
vm.runInContext('var pluginHandler = new ('+handler.prepExports()+')();',context,{timeout:2000});
const plugin=context.pluginHandler.iosAssistance;
function refresh(id,agent={id:4294967280}){headers.innerHTML='';pages.innerHTML='';context.currentNode={_id:id,agent};plugin.onDeviceRefreshEnd(id);}
refresh('node/team/a');
assert(find('iosAssistanceTab'));const host=find('iosAssistanceHost'),frame=find('iosAssistanceFrame');assert(host&&frame);
assert.equal(host.parent,page);assert.equal(host.style.display,'');
const address=new URL(frame.src);assert.equal(address.origin,'https://example.invalid');assert.equal(address.pathname,'/team/ios-assist.html');assert.equal(address.search,'');
assert.equal(new URLSearchParams(address.hash.slice(1)).get('node'),'node/team/a');
refresh('node/team/a');assert.equal(find('iosAssistanceHost'),host);assert.equal(find('iosAssistanceFrame'),frame);
find('p19ph-iosAssistanceTab').classList.remove('on');plugin.syncVisibility();assert.equal(host.style.display,'none');
find('p19ph-iosAssistanceTab').classList.add('on');plugin.syncVisibility();assert.equal(host.style.display,'');
plugin.goPageStart(19);assert.equal(frame.messages.length,0);
plugin.goPageStart(10);assert.equal(frame.messages.length,1);assert.equal(frame.messages[0][1],'https://example.invalid');assert.equal(frame.messages[0][0].action,'leave');
refresh('node/team/b');assert.notEqual(find('iosAssistanceFrame'),frame);assert.equal(new URLSearchParams(new URL(find('iosAssistanceFrame').src).hash.slice(1)).get('node'),'node/team/b');
refresh('node/team/desktop',{id:4});assert.equal(find('iosAssistanceHost'),null);assert.equal(find('iosAssistanceTab'),null);
refresh('node/team/legacy',{id:0,core:'MeshCentral iOS Rust 0.3.0'});assert(find('iosAssistanceHost'));
refresh('node/team/bad?query');assert.equal(find('iosAssistanceHost'),null);
console.log('PASS: actual MeshCentral plugin export serializer, device recognition, domain URL, same-device refresh preserves relay iframe, cross-device teardown and page-leave notification.');
