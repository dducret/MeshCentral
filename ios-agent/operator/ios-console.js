// SPDX-License-Identifier: Apache-2.0
"use strict";
// Original UI-only helpers. No storage, fetch, external dependency or remote commands.
globalThis.IOSConsole = (() => {
    const bytes = text => new TextEncoder().encode(text).length;
    const builtins = [
        {title:"Vérifier le Wi-Fi",steps:["Ouvrez Réglages, puis Wi-Fi. Revenez dans l’app pour confirmer.","Vérifiez que le Wi-Fi est activé et qu’un réseau est sélectionné. Indiquez le résultat dans le chat, sans mot de passe.","Essayez d’ouvrir une page habituelle dans Safari. Revenez nous dire si elle se charge."]},
        {title:"Diagnostiquer la messagerie",steps:["Ouvrez votre application de messagerie et relevez le message d’erreur éventuel, sans partager de mot de passe.","Revenez dans le chat et décrivez si le problème concerne l’envoi, la réception ou les deux.","Vérifiez si une page habituelle s’ouvre dans Safari. Ne supprimez aucun compte pendant ce diagnostic."]},
        {title:"Vérifier le stockage",steps:["Ouvrez Réglages, Général, puis Stockage iPad ou Stockage iPhone. Attendez le calcul.","Indiquez l’espace disponible dans le chat. Ne supprimez aucun document pour le moment.","Repérez une catégorie volumineuse et demandez au technicien quelle action serait adaptée."]},
        {title:"Préparer une impression",steps:["Vérifiez que l’iPad et l’imprimante utilisent le même réseau Wi-Fi.","Ouvrez le document à imprimer, puis son menu de partage et l’option Imprimer si disponible.","Relevez si l’imprimante apparaît dans la liste. Revenez dans le chat avant de lancer l’impression."]},
        {title:"Vérifier les autorisations d’une app",steps:["Ouvrez Réglages et recherchez l’application concernée.","Repérez l’autorisation liée au problème. Décrivez son état dans le chat.","Modifiez uniquement l’autorisation convenue avec le technicien, puis testez l’application."]}
    ];
    const tips = [
        "Aucun problème détecté dans les mesures disponibles.",
        "Réseau indisponible : vérifiez Wi-Fi ou connexion cellulaire sur l’appareil.",
        "Aucune image récente : vérifiez la diffusion iPadOS, le verrouillage ou un contenu protégé.",
        "Connexion lente : laissez la qualité s’adapter et vérifiez la réception réseau.",
        "Mode Faibles données actif : la fluidité peut être réduite.",
        "Température élevée : laissez refroidir l’appareil."
    ];
    const states = {disconnected:"Non connecté",available:"Appareil disponible",offline:"Appareil hors ligne",
        requested:"Demande envoyée",pairing:"Connexion au relais",consent:"Autorisation sur l’appareil attendue",
        sharing:"Assistance active",closed:"Session terminée",error:"Connexion interrompue"};
    const validTemplate = item => item && typeof item.title === 'string' && item.title.trim() && bytes(item.title) <= 100 &&
        Array.isArray(item.steps) && item.steps.length >= 1 && item.steps.length <= 20 &&
        item.steps.every(step => typeof step === 'string' && step.trim() && !/[\r\n]/.test(step) && bytes(step) <= 800);
    class Console {
        constructor(options) {
            this.ui = options.$; this.download = options.download; this.applyPlan = options.applyPlan;
            this.canChangePlan = options.canChangePlan; this.templates = builtins.map(t=>({...t,steps:[...t.steps]}));
            this.report = null; this.lastHealth = null; this.ui('reportExport').disabled = true;
            this.refreshTemplates();
            this.ui('templateUse').onclick = () => {
                if (!this.canChangePlan()) { this.ui('templateStatus').textContent = "Arrêtez le parcours courant avant de charger un modèle."; return; }
                const item = this.templates[Number(this.ui('templates').value)];
                if (item) this.applyPlan(item.steps.join('\n'));
            };
            this.ui('templateSave').onclick = () => {
                const item = {title:this.ui('templateName').value.trim(), steps:this.ui('guidePlan').value.split(/\r?\n/).map(s=>s.trim()).filter(Boolean)};
                if (!validTemplate(item) || this.templates.length >= 25 || bytes(JSON.stringify({schema:1,templates:[...this.templates,item]},null,2))>262144) { this.ui('templateStatus').textContent = "Titre requis (100 octets), 1 à 20 étapes de 800 octets. 25 modèles et 256 Kio maximum."; return; }
                this.templates.push(item); this.refreshTemplates(); this.ui('templates').value = String(this.templates.length-1);
                this.ui('templateStatus').textContent = "Modèle mémorisé pour cette page. Exportez la bibliothèque pour le conserver.";
            };
            this.ui('templateExport').onclick = () => this.download(JSON.stringify({schema:1,templates:this.templates},null,2),'meshcentral-parcours.json','application/json');
            this.ui('templateImport').onchange = async () => {
                const file = this.ui('templateImport').files[0]; this.ui('templateImport').value = '';
                if (!file || file.size > 262144) { this.ui('templateStatus').textContent = "Fichier trop volumineux (256 Kio maximum)."; return; }
                try {
                    const items = Console.parseTemplates(await file.text());
                    // Replace only the explicitly imported library, never the running guide.
                    this.templates = items; this.refreshTemplates(); this.ui('templateStatus').textContent = "Bibliothèque importée. Le parcours en cours reste inchangé.";
                } catch { this.ui('templateStatus').textContent = "Bibliothèque invalide. Aucun modèle modifié."; }
            };
            this.ui('reportExport').onclick = () => {
                if (!this.report) return;
                const result = this.exportReport(this.ui('reportContent').checked === true);
                this.download(JSON.stringify(result,null,2),'meshcentral-intervention.json','application/json');
            };
            this.ui('reportClear').onclick = () => { this.report=null; this.ui('reportNotes').value=''; this.ui('reportContent').checked=false; this.refreshReport(); };
        }
        static parseTemplates(text) {
            if (bytes(text) > 262144) throw Error('size');
            const object = JSON.parse(text);
            if (object.schema !== 1 || !Array.isArray(object.templates) || !object.templates.length || object.templates.length > 25 || !object.templates.every(validTemplate)) throw Error('schema');
            const items=object.templates.map(t=>({title:t.title.trim(),steps:t.steps.map(s=>s.trim())}));
            if(bytes(JSON.stringify({schema:1,templates:items},null,2))>262144) throw Error('size');
            return items;
        }
        refreshTemplates() {
            this.ui('templates').replaceChildren();
            this.templates.forEach((item,index) => {const option=document.createElement('option');option.value=String(index);option.textContent=item.title;this.ui('templates').appendChild(option);});
            this.ui('templates').value='0';
        }
        start() {
            this.lastHealth = null;
            this.report = {schema:1,startedAt:new Date().toISOString(),endedAt:null,events:[],truncated:false};
            this.ui('reportNotes').value=''; this.ui('reportContent').checked=false;
            this.event('session_requested'); this.refreshReport();
        }
        event(kind, detail = {}) {
            if (!this.report || this.report.endedAt) return;
            if (this.report.events.length >= 500) {this.report.truncated=true;this.refreshReport();return;}
            // Call sites supply local event kinds. Allowlist fields; never copy a network object.
            const item = {at:new Date().toISOString(),kind};
            for (const key of ['step','total','bytes','code']) if (Number.isInteger(detail[key]) && detail[key]>=0 && detail[key]<=16777216) item[key]=detail[key];
            if (typeof detail.text==='string') item.text=detail.text.slice(0,1024);
            this.report.events.push(item); this.refreshReport();
        }
        finish(reason) {
            if (!this.report || this.report.endedAt) return;
            this.event('session_ended'); this.report.endedAt=new Date().toISOString();
            this.report.result=['stopped','connection_lost','timeout','invalid_data','page_left'].includes(reason)?reason:'connection_lost';
            this.refreshReport();
        }
        refreshReport() {
            this.ui('reportExport').disabled=!this.report;
            this.ui('reportSummary').textContent=this.report ? `${this.report.events.length} événements · ${this.report.endedAt?'session terminée':'session en cours'}${this.report.truncated?' · historique limité':''}` : 'Aucune intervention à exporter.';
        }
        exportReport(includeContent) {
            if (!this.report) return null;
            const result={schema:1,startedAt:this.report.startedAt,endedAt:this.report.endedAt,result:this.report.result||'in_progress',truncated:this.report.truncated,
                contentIncluded:includeContent,events:this.report.events.map(item=>{const row={...item};if(!includeContent)delete row.text;return row;})};
            if (includeContent) result.notes=this.ui('reportNotes').value.slice(0,4000);
            return result;
        }
        state(value) {
            this.ui('sessionState').textContent=states[value]||states.disconnected;
            if (value !== 'sharing') {
                this.ui('streamFreshness').textContent='Aucune image en direct : session inactive.';
                this.ui('sessionTime').textContent='';
                this.ui('healthAdvice').textContent='Les mesures seront disponibles pendant une session autorisée.';
            }
        }
        compatibility(version, timing) {
            this.ui('agentCompatibility').textContent = `Agent ${version || 'version non annoncée'} · ${timing ? 'durée restante disponible' : 'durée restante non annoncée par cet agent'}`;
        }
        freshness(frameAge, telemetryAge, hasFrame) {
            this.ui('streamFreshness').textContent = !hasFrame ? 'En attente de la première image.' :
                (frameAge >= 10000 ? `Image ancienne : dernière image affichée il y a ${Math.floor(frameAge/1000)} s. Elle ne prouve pas que le partage continue.` : `Dernière image affichée il y a ${Math.floor(frameAge/1000)} s.`);
            if (telemetryAge < 10000 && frameAge >= 10000) {
                this.ui('healthAdvice').textContent='La télémétrie arrive mais aucune image récente n’est affichée. Vérifiez la diffusion, un contenu protégé ou le rendu du navigateur.';
            }
        }
        device(node) {
            if (!node) {this.ui('deviceIdentity').textContent='Appareil non accessible dans cette session MeshCentral.';return;}
            const core=typeof node.agent?.core==='string'?node.agent.core:'';
            const online=(node.conn&1)!==0;
            const role=core.includes('[broadcast-ready]')?'diffusion prête':(core.includes('[app-connected]')?'app connectée, diffusion à démarrer':'état de diffusion non annoncé');
            this.ui('deviceIdentity').textContent=`${String(node.name||'Appareil').slice(0,128)} · Agent iOS / Rust · ${online?role:'hors ligne'}`;
        }
        diagnostics(metrics, ageMS) {
            const code=Number.isInteger(metrics.healthCode)&&metrics.healthCode>=0&&metrics.healthCode<tips.length?metrics.healthCode:0;
            this.ui('healthAdvice').textContent=ageMS>=10000?'Aucune télémétrie récente : le flux peut être interrompu. Vérifiez le réseau et la diffusion.':tips[code];
            const network={wifi:'Wi-Fi',cellular:'cellulaire',ethernet:'Ethernet',other:'autre interface'}[metrics.networkInterface]||'non communiqué';
            const state={available:'disponible',unavailable:'indisponible',requiresConnection:'connexion à établir'}[metrics.networkState]||'état inconnu';
            this.ui('networkInfo').textContent=`Réseau : ${network} · ${state}${metrics.constrained?' · faibles données':''}${metrics.expensive?' · connexion tarifée':''}${metrics.lowPower?' · économie d’énergie':''}`;
            if (Number.isInteger(metrics.remainingSeconds) && metrics.remainingSeconds>=0 && metrics.remainingSeconds<=600) {
                const remaining=Math.max(0,metrics.remainingSeconds-Math.floor(Math.max(0,ageMS)/1000));
                this.ui('sessionTime').textContent=ageMS>=10000 ? 'Durée restante inconnue : télémétrie ancienne.' :
                    `Temps restant annoncé : ${Math.floor(remaining/60)} min ${remaining%60} s · toute relance exige un nouvel accord.`;
            } else this.ui('sessionTime').textContent='Durée restante non communiquée par cet agent.';
            if (this.lastHealth!==code) {this.lastHealth=code;this.event('health',{code});}
        }
    }
    return Console;
})();
