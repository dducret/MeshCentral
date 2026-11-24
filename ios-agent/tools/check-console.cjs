// SPDX-License-Identifier: Apache-2.0
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const elements=new Map(),downloads=[];
function element(id){if(!elements.has(id))elements.set(id,{value:'',checked:false,children:[],files:[],textContent:'',appendChild(e){this.children.push(e);},replaceChildren(){this.children=[];}});return elements.get(id);}
const sandbox={TextEncoder,console,document:{createElement:()=>({})}};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname,'../operator/ios-console.js'),'utf8'),sandbox);
const Console=sandbox.IOSConsole;
let allowed=true,applied='';
const instance=new Console({$:element,download:(...args)=>downloads.push(args),canChangePlan:()=>allowed,applyPlan:text=>applied=text});
(async()=>{
    assert.equal(instance.templates.length,5);
    element('templates').value='0';element('templateUse').onclick();assert(applied.includes('Wi-Fi'));
    allowed=false;applied='';element('templateUse').onclick();assert.equal(applied,'');
    element('templateName').value='<img src=x onerror=alert(1)>';
    element('guidePlan').value='Première étape\nDeuxième étape';element('templateSave').onclick();
    assert.equal(instance.templates.length,6);assert.equal(element('templates').children.at(-1).textContent,element('templateName').value);
    element('templateExport').onclick();
    const restored=Console.parseTemplates(downloads.at(-1)[0]);assert.equal(restored.length,6);
    for(const input of ['{}','null',JSON.stringify({schema:1,templates:[{title:'X',steps:['a\nb']}]}),JSON.stringify({schema:1,templates:[{title:'X',steps:['é'.repeat(401)]}]}),' '.repeat(262145)]){
        assert.throws(()=>Console.parseTemplates(input));
    }
    const before=instance.templates;
    element('templateImport').files=[{size:10,text:async()=>'invalid'}];await element('templateImport').onchange();assert.equal(instance.templates,before);
    element('templateImport').files=[{size:100,text:async()=>JSON.stringify({schema:1,templates:[{title:'Clean',steps:['Step'],ignored:'secret'}],token:'secret'})}];
    await element('templateImport').onchange();assert.equal(instance.templates.length,1);assert.equal(instance.templates[0].ignored,undefined);
    instance.start();instance.event('technician_message',{text:'secret',token:'not allowed',step:1});
    assert.equal(instance.exportReport(false).events.at(-1).text,undefined);
    assert(!JSON.stringify(instance.exportReport(false)).includes('secret'));
    assert.equal(instance.exportReport(true).events.at(-1).text,'secret');
    assert.equal(instance.exportReport(true).events.at(-1).token,undefined);
    for(let i=0;i<600;i++)instance.event('health',{code:0});
    assert.equal(instance.report.events.length,500);assert.equal(instance.report.truncated,true);
    instance.finish('stopped');const ended=instance.report.endedAt;instance.finish('timeout');assert.equal(instance.report.endedAt,ended);assert.equal(instance.report.result,'stopped');
    instance.event('late_event');assert.equal(instance.report.events.length,500);
    instance.start();assert.equal(instance.report.events.length,1);assert.equal(element('reportNotes').value,'');assert.equal(element('reportContent').checked,false);
    instance.diagnostics({healthCode:5,networkInterface:'wifi',networkState:'available'},0);assert.match(element('healthAdvice').textContent,/Température/);
    instance.diagnostics({},11000);assert.match(element('healthAdvice').textContent,/télémétrie/);
    instance.diagnostics({remainingSeconds:120},1500);assert.match(element('sessionTime').textContent,/1 min 59 s/);
    instance.diagnostics({remainingSeconds:120},10000);assert.match(element('sessionTime').textContent,/inconnue/);
    instance.diagnostics({remainingSeconds:601},0);assert.match(element('sessionTime').textContent,/non communiquée/);
    instance.freshness(9999,0,true);assert(!element('streamFreshness').textContent.includes('ancienne'));
    instance.freshness(10000,0,true);assert.match(element('streamFreshness').textContent,/Image ancienne/);
    assert.match(element('healthAdvice').textContent,/rendu du navigateur/);
    instance.freshness(11000,11000,false);assert.match(element('streamFreshness').textContent,/première image/);
    instance.compatibility('0.3.0',false);assert.match(element('agentCompatibility').textContent,/non annoncée/);
    instance.state('closed');assert.match(element('streamFreshness').textContent,/inactive/);assert.equal(element('sessionTime').textContent,'');
    console.log('PASS: console templates/import bounds/text safety, report opt-in/allowlist/limits/cleanup, diagnostic recommendations.');
})().catch(error=>{console.error(error);process.exitCode=1;});
