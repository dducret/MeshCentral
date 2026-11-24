// SPDX-License-Identifier: Apache-2.0
"use strict";
// Original, dependency-free MeshCentral p=2 browser adapter.
const $ = id => document.getElementById(id);
const MAX = 2 * 1024 * 1024, CHUNK = 8192;
const utf8 = new TextEncoder();
const validName = name => typeof name === "string" && utf8.encode(name).length <= 128 &&
    name.length > 0 && !/[\/\\\x00-\x1f\x7f]/.test(name) && name !== "." && name !== "..";
const validID = id => typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id);
const hash = async data => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", data)), n => n.toString(16).padStart(2,"0")).join("");
const url = (path, query) => { const u = new URL(path, location.href); u.protocol = "wss:"; u.search = new URLSearchParams(query); return u; };
let control, relay, ready = false, pairing = false, selected = "", cookie = "", rcookie = "", deadline;
let incoming = null, outgoing = null, received = null, snapshotImage = null, snapshotID = null;
let strokes = [], currentStroke = null, decoding = false, frameEpoch = 0;
let screenHidden = false, screenEpoch = 0;
let guide = null, guideSupported = false;
let timingSupported = false;
let consoleUI = null, telemetryAt = 0, shownFrameAt = 0, firstReadyAt = 0;
const devices = new Map();
const fragment = new URLSearchParams(location.hash.slice(1));
const requestedNode = fragment.get('node') || '';
const isIOS = node => node?.agent && (node.agent.id === 4294967280 || (typeof node.agent.core === 'string' && node.agent.core.startsWith('MeshCentral iOS Rust ')));
const canConnect = node => !!(node && (node.conn & 1) && (node.agent?.caps & 1));
const validNode = id => typeof id === 'string' && id.length <= 256 && /^node\/[^/]*\/[^/?#\s]+$/.test(id);
let metrics = { version: "0.4.0", stage: "disconnected", frames: 0, bytes: 0 };
const screen = $("screen"), screenContext = screen.getContext("2d");
const annotation = $("annotation"), annotationContext = annotation.getContext("2d");
function status(message) { $("status").textContent = message; }
function screenVisibility(hidden) {
    if (screenHidden === hidden) return;
    screenHidden = hidden; screenEpoch++;
    screenContext.clearRect(0, 0, screen.width, screen.height);
    screen.hidden = hidden;
    $("capture").disabled = $("fullscreen").disabled = hidden;
    if (hidden && document.fullscreenElement === screen) document.exitFullscreen?.().catch(() => {});
    shownFrameAt = 0; firstReadyAt = performance.now();
    $("streamFreshness").textContent = hidden ? "Écran masqué sur l’appareil." : "En attente d’une nouvelle image.";
}
function transferStatus(direction, text, completed = null, total = 1) {
    $(direction + 'Status').textContent = text;
    const bar = $(direction + 'Progress');
    bar.hidden = completed === null;
    if (completed !== null) { bar.max = total; bar.value = completed; }
}
function send(action, fields = {}) {
    if (!ready || relay?.readyState !== WebSocket.OPEN) return false;
    const text = JSON.stringify({ type:"iosAssist", v:1, action, ...fields });
    if (utf8.encode(text).length > 16384) return false;
    relay.send(text); return true;
}
function log(text, local) {
    consoleUI?.event(local ? 'technician_message' : 'device_message', {text});
    const div = document.createElement("div"); div.className = "bubble";
    div.textContent = (local ? "Vous : " : "iPhone : ") + text; $("messages").appendChild(div);
    while ($("messages").children.length > 40) $("messages").firstElementChild.remove();
    $("messages").scrollTop = $("messages").scrollHeight;
}
function end(message, reason = 'connection_lost') {
    consoleUI?.finish(reason); consoleUI?.state(reason === 'stopped' || reason === 'page_left' ? 'closed' : 'error');
    frameEpoch++; screenEpoch++; screenHidden = false; screen.hidden = false; $("fullscreen").disabled = false;
    clearTimeout(deadline); ready = pairing = false; timingSupported = false;
    transferStatus('incoming', ''); transferStatus('outgoing', '');
    $('agentCompatibility').textContent='';
    if (relay) { const old = relay; relay = null; old.close(); }
    incoming = outgoing = received = null; snapshotID = null;
    snapshotImage?.close(); snapshotImage = null; strokes = []; currentStroke = null;
    cookie = rcookie = ""; metrics.stage = "closed"; $("messages").replaceChildren(); $("chat").value = ""; $("file").value = "";
    for (const id of ["send","file","capture","stop","undo","annotate","cancelTransfer"]) $(id).disabled = true;
    for (const id of ["accept","reject","download"]) $(id).hidden = true;
    $("offer").textContent = $("transfer").textContent = "";
    $("connect").disabled = control?.readyState !== WebSocket.OPEN || !canConnect(devices.get($("nodes").value));
    $("nodes").disabled = !!requestedNode;
    screenContext.clearRect(0,0,screen.width,screen.height); redraw();
    guide = null; guideSupported = false; $("guidePlan").value = $("guideNextText").value = "";
    $("guideAttach").checked = false; renderGuide();
    status(message);
}
function guideActive() {
    return guide && guide.status !== "stopped" && !(guide.status === "done" && guide.index === guide.steps.length);
}
function renderGuide() {
    const active = guideActive();
    $("guideStart").disabled = !guideSupported || !!active;
    $("guidePlan").disabled = !!active;
    $("guideAttach").disabled = !guideSupported || !snapshotID;
    $("guideControls").hidden = !active;
    $("guideNext").disabled = !guideSupported || !active || !!guide.pending || !["idle","done"].includes(guide.status);
    $("guideStop").disabled = !active;
    $("guideSteps").replaceChildren();
    if (!guide) {
        $("guideStatus").textContent = guideSupported ? "Préparez le parcours, puis envoyez la première étape." : "Guidage indisponible : mettez l’agent à jour et vérifiez le droit Chat / Notify.";
        return;
    }
    guide.steps.forEach((text, i) => {
        const row = document.createElement("li"); row.textContent = text;
        row.className = i + 1 < guide.index || (i + 1 === guide.index && guide.status === "done") ? "done" : (i + 1 === guide.index ? "current" : "");
        $("guideSteps").appendChild(row);
    });
    const labels = { idle:"Étape non envoyée.", sending:"Envoi de l’étape…", waiting:"Attente de la confirmation sur l’appareil.",
        help:"La personne demande de l’aide. Répondez dans le chat avant de poursuivre.", done:guide.index === guide.steps.length ? "Parcours terminé." : "Étape confirmée. Vous pouvez envoyer la suivante.", stopped:"Guidage arrêté. Le chat reste disponible." };
    $("guideStatus").textContent = "Étape " + (guide.pending?.step || guide.index) + "/" + guide.steps.length + " — " + labels[guide.status];
}
function dispatchGuideStep() {
    if (!guideSupported || !guideActive() || guide.pending || !["idle","done"].includes(guide.status)) return;
    const text = $("guideNextText").value.trim(), step = guide.index + 1;
    if (!text || utf8.encode(text).length > 800 || step > guide.steps.length) { $("guideStatus").textContent = "Une instruction doit contenir entre 1 et 800 octets UTF-8."; return; }
    const fields = {id:guide.id,step,total:guide.steps.length,text};
    if ($("guideAttach").checked) {
        if (!snapshotID || !snapshotImage) { $("guideStatus").textContent = "Recevez d’abord une capture ou décochez la pièce jointe."; return; }
        fields.captureID = snapshotID; fields.strokes = strokes.filter(s => s.points.length >= 2);
    }
    if (!send("guideStep",fields)) { $("guideStatus").textContent = "Envoi impossible ou annotations trop volumineuses. Réduisez les traits et réessayez."; return; }
    guide.steps[step-1] = text;
    guide.pending = {step, previous:guide.status, sentAt:performance.now()}; guide.status = "sending"; renderGuide();
}
function redraw() {
    annotationContext.clearRect(0,0,annotation.width,annotation.height);
    if (snapshotImage) annotationContext.drawImage(snapshotImage,0,0);
    annotationContext.strokeStyle = "#f02035"; annotationContext.lineWidth = 3; annotationContext.lineCap = "round";
    for (const stroke of strokes) {
        annotationContext.beginPath();
        stroke.points.forEach(([x,y], i) => { if (!i) annotationContext.moveTo(x*annotation.width,y*annotation.height); else annotationContext.lineTo(x*annotation.width,y*annotation.height); });
        annotationContext.stroke();
    }
}
function download(data, name, type = "application/octet-stream") {
    const address = URL.createObjectURL(new Blob([data],{type}));
    const anchor = document.createElement("a"); anchor.href = address; anchor.download = name; anchor.click();
    setTimeout(() => URL.revokeObjectURL(address), 1000);
}
async function message(value) {
    if (!value || value.type !== "iosAssist" || value.v !== 1) return;
    if (value.action === "ready") {
        clearTimeout(deadline); ready = true; metrics.stage = "sharing";
        $("send").disabled = value.chatAllowed !== true; $("file").disabled = value.documentsAllowed !== true; $("capture").disabled = false;
        $("cancelTransfer").disabled = false;
        guideSupported = value.guidedAssistance === 1 && value.chatAllowed === true; renderGuide();
        firstReadyAt = performance.now(); telemetryAt = firstReadyAt; shownFrameAt = 0;
        timingSupported = value.sessionTiming === 1;
        delete metrics.remainingSeconds;
        consoleUI?.freshness(0, 0, false);
        consoleUI?.state('sharing'); consoleUI?.event('session_accepted');
        if (value.consoleVersion === 1) {
            metrics.featureVersion = 'console-1';
            if (typeof value.agentVersion === 'string' && /^[0-9.]{1,20}$/.test(value.agentVersion)) metrics.agentVersion=value.agentVersion;
        }
        consoleUI?.compatibility(metrics.agentVersion, timingSupported);
        status("Session acceptée sur l’appareil. Lecture seule ; documents avec confirmation."); return;
    }
    if (!ready) return;
    switch(value.action) {
    case "screenVisibility":
        if (typeof value.hidden === "boolean") screenVisibility(value.hidden);
        break;
    case "guideStatus": {
        if (!guideSupported || !guide || value.id !== guide.id) return;
        if (!Number.isInteger(value.step) || value.step < 1 || value.step > guide.steps.length || value.total !== guide.steps.length || !["waiting","help","done","stopped"].includes(value.status)) throw Error();
        if ((value.status !== "stopped" && value.step !== (guide.pending?.step || guide.index)) || guide.status === "stopped") return;
        const changed = guide.status !== value.status || guide.index !== value.step;
        if (guide.pending && value.status !== "stopped") {
            log("Étape " + value.step + "/" + value.total + " : " + guide.steps[value.step-1],true);
            $("guideNextText").value = guide.steps[value.step] || "";
            $("guideAttach").checked = false;
        }
        guide.index = value.step; guide.status = value.status; guide.pending = null; renderGuide();
        if (changed) consoleUI?.event('guide_' + value.status, {step:value.step,total:value.total});
        if (changed && value.status !== "waiting") log("Étape " + value.step + " : " + ({help:"J’ai besoin d’aide.",done:"Étape terminée.",stopped:"Guidage arrêté."})[value.status],false);
        break;
    }
    case "guideError":
        if (!guide || value.id !== guide.id || value.step !== guide.pending?.step) return;
        guide.status = guide.pending.previous; guide.pending = null; renderGuide();
        $("guideStatus").textContent = value.reason === "captureUnavailable" ? "La capture n’est plus disponible sur l’appareil. Demandez-en une nouvelle ou envoyez l’étape sans image." : "Étape refusée. Vérifiez le parcours ou arrêtez-le avant de recommencer.";
        break;
    case "captureDeclined": $("transfer").textContent = "La personne a refusé la capture."; break;
    case "chat":
        if (typeof value.text !== "string" || utf8.encode(value.text).length > 1024) throw Error();
        log(value.text,false); break;
    case "diagnostics":
        for (const key of ["fps","kilobitsPerSecond","roundTripMS","sendMS","frameAgeMS"]) {
            if (typeof value[key] === "number" && Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 600000) metrics[key] = value[key];
        }
        for (const [key,max] of [['qualityLevel',2],['healthCode',5],['thermalState',3]]) {
            if (Number.isInteger(value[key]) && value[key]>=0 && value[key]<=max) metrics[key]=value[key];
        }
        for (const key of ['constrained','expensive','lowPower']) if (typeof value[key]==='boolean') metrics[key]=value[key];
        if (['unknown','available','unavailable','requiresConnection'].includes(value.networkState)) metrics.networkState=value.networkState;
        if (['unknown','wifi','cellular','ethernet','other'].includes(value.networkInterface)) metrics.networkInterface=value.networkInterface;
        if (timingSupported && Number.isInteger(value.remainingSeconds) && value.remainingSeconds >= 0 && value.remainingSeconds <= 600) metrics.remainingSeconds = value.remainingSeconds;
        else delete metrics.remainingSeconds;
        telemetryAt = performance.now(); consoleUI?.diagnostics(metrics,0);
        $("metrics").textContent = (metrics.fps || 0).toFixed(1)+" images/s · "+(metrics.kilobitsPerSecond || 0).toFixed(0)+" kbit/s · RTT relais "+(metrics.roundTripMS || 0).toFixed(0)+" ms";
        break;
    case "offer":
        if (!validID(value.id) || !validName(value.name) || !Number.isInteger(value.size) || value.size < 1 || value.size > MAX ||
            !["document","capture"].includes(value.kind) || !/^[0-9a-f]{64}$/i.test(value.sha256)) throw Error();
        if (incoming || received) { send("cancel",{id:value.id}); return; }
        incoming = {id:value.id,name:value.name,size:value.size,kind:value.kind,sha256:value.sha256,bytes:null,offset:0,updated:performance.now()};
        transferStatus('incoming', 'Proposition reçue : acceptez ou refusez ce transfert.');
        $("offer").textContent = (value.kind === "capture" ? "Capture : " : "Document : ")+value.name+" ("+value.size+" octets)";
        $("accept").hidden = $("reject").hidden = false; break;
    case "chunk": {
        const item = incoming;
        if (!item?.bytes || value.id !== item.id || value.offset !== item.offset || typeof value.data !== "string" || value.data.length > 10924) throw Error();
        const decoded = atob(value.data);
        if (!decoded.length || decoded.length > CHUNK || item.offset + decoded.length > item.size) throw Error();
        for(let i=0;i<decoded.length;i++) item.bytes[item.offset+i] = decoded.charCodeAt(i);
        item.offset += decoded.length; item.updated = performance.now();
        $("transfer").textContent = "Réception : "+Math.round(item.offset*100/item.size)+" %";
        transferStatus('incoming', item.offset === item.size ? 'Vérification de l’intégrité…' : 'Réception en cours', item.offset, item.size);
        if(item.offset === item.size) {
            const epoch = frameEpoch;
            if(await hash(item.bytes) !== item.sha256.toLowerCase()) {
                if (incoming === item) incoming = null;
                throw Error();
            }
            if(epoch !== frameEpoch || !ready) return;
            if(item.kind === "capture") {
                const image = await createImageBitmap(new Blob([item.bytes],{type:"image/jpeg"}));
                if(epoch !== frameEpoch || !ready) { image.close(); return; }
                if(image.width > 1920 || image.height > 1920) { image.close(); throw Error(); }
                snapshotImage?.close(); snapshotImage = image; snapshotID = item.id; strokes = [];
                $("guideAttach").checked = false; renderGuide();
                annotation.width = image.width; annotation.height = image.height; redraw();
                $("undo").disabled = $("annotate").disabled = false;
            } else { received = item; $("download").hidden = false; }
            incoming = null;
            transferStatus('incoming', 'Réception terminée, intégrité vérifiée.', item.size, item.size);
            $("offer").textContent = ""; $("transfer").textContent = "Réception terminée, intégrité SHA-256 vérifiée.";
            consoleUI?.event(item.kind === 'capture' ? 'capture_received' : 'document_received', {bytes:item.size});
        }
        send("ack",{id:item.id,offset:item.offset}); break;
    }
    case "ack": {
        const item = outgoing;
        if(!item || value.id !== item.id || value.offset !== item.awaiting) return;
        item.updated = performance.now();
        if(value.offset === item.bytes.length) { consoleUI?.event('document_sent',{bytes:item.bytes.length}); outgoing = null; $("transfer").textContent = "Envoi terminé."; transferStatus('outgoing', 'Réception confirmée par l’appareil.', item.bytes.length, item.bytes.length); return; }
        const start = value.offset, next = Math.min(item.bytes.length,start+CHUNK);
        const encoded = btoa(String.fromCharCode(...item.bytes.subarray(start,next)));
        item.awaiting = next;
        send("chunk",{id:item.id,offset:start,data:encoded});
        $("transfer").textContent = "Envoi confirmé : "+Math.round(start*100/item.bytes.length)+" %";
        transferStatus('outgoing', 'Envoi accepté — progression confirmée par le destinataire', start, item.bytes.length); break;
    }
    case "cancel":
        if(value.id === incoming?.id) { transferStatus('incoming', 'Transfert annulé par l’appareil.'); incoming = null; $("accept").hidden = $("reject").hidden = true; $("offer").textContent = ""; }
        if(value.id === outgoing?.id) { outgoing = null; transferStatus('outgoing', value.reason === 'rejected' ? 'Document refusé sur l’appareil.' : (value.reason === 'timeout' ? 'Délai de transfert dépassé.' : 'Transfert refusé ou annulé sur l’appareil.')); }
        $("transfer").textContent = "Transfert annulé ou délai dépassé."; break;
    }
}
async function frame(buffer) {
    if(!ready || screenHidden || buffer.byteLength > 524304 || buffer.byteLength < 4) return;
    let bytes = new Uint8Array(buffer), view = new DataView(buffer), cmd = view.getUint16(0), length = view.getUint16(2);
    if(cmd === 27) {
        if(bytes.length < 16 || length !== 8 || view.getUint32(4) !== bytes.length - 8) throw Error();
        bytes = bytes.subarray(8); view = new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
        cmd = view.getUint16(0); length = bytes.length;
    }
    if(length !== bytes.length) throw Error();
    if(cmd === 7) {
        if(length !== 8) throw Error();
        const width = view.getUint16(4), height = view.getUint16(6);
        if(!width || !height || width > 1920 || height > 1920) throw Error();
        screen.width = width; screen.height = height; return;
    }
    if(cmd !== 3 || length < 12 || view.getUint16(4) !== 0 || view.getUint16(6) !== 0 || decoding) return;
    const epoch = screenEpoch; decoding = true;
    try {
        const image = await createImageBitmap(new Blob([bytes.subarray(8)],{type:"image/jpeg"}));
        if(epoch === screenEpoch && ready && !screenHidden && image.width <= 1920 && image.height <= 1920) {
            screen.width = image.width; screen.height = image.height; screenContext.drawImage(image,0,0);
            metrics.frames++; metrics.bytes += bytes.length;
            shownFrameAt = performance.now();
        }
        image.close();
    } catch (error) {
        if (epoch === screenEpoch && ready && !screenHidden) throw error;
    } finally { decoding = false; }
}
function startRelay() {
    if(!pairing || relay || !cookie || !rcookie) return;
    const id = crypto.randomUUID(), node = selected;
    relay = new WebSocket(url("meshrelay.ashx",{browser:1,p:2,nodeid:node,id,auth:cookie}));
    relay.binaryType = "arraybuffer"; const current = relay;
    consoleUI?.state('pairing');
    current.onopen = () => {
        if(relay !== current || !pairing || control?.readyState !== WebSocket.OPEN) return;
        const agent = "*/" + location.pathname.split("/").slice(1,-1).join("/");
        const path = (agent.endsWith("/") ? agent : agent+"/") + "meshrelay.ashx?";
        control.send(JSON.stringify({action:"msg",type:"tunnel",nodeid:node,usage:2,
            value:path + new URLSearchParams({p:2,nodeid:node,id,rauth:rcookie})}));
        cookie = rcookie = "";
    };
    current.onmessage = event => {
        if(relay !== current) return;
        if(typeof event.data === "string") {
            if(event.data === "c" || event.data === "cr") {
                consoleUI?.state('consent'); consoleUI?.event(event.data === 'cr' ? 'recorded_session' : 'awaiting_consent');
                current.send("2"); status(event.data === "cr" ? "Session enregistrée. Attente de l’accord sur l’iPhone…" : "Attente de l’accord sur l’iPhone…"); return;
            }
            if(utf8.encode(event.data).length > 16384) { end("Message trop volumineux.",'invalid_data'); return; }
            let value; try { value = JSON.parse(event.data); } catch { end("Message invalide.",'invalid_data'); return; }
            if (!value || typeof value!=='object' || Array.isArray(value)) { end('Message invalide.','invalid_data'); return; }
            if (value.ctrlChannel === '102938' && value.type === 'ping') { current.send(JSON.stringify({ctrlChannel:'102938',type:'pong'})); return; }
            if (value.ctrlChannel === '102938' && value.type === 'pong') return;
            if(value.type === "console") { status(typeof value.msg === "string" ? value.msg : "Session autorisée."); return; }
            message(value).catch(() => { if(relay === current) end("Session arrêtée : données invalides."); });
        } else frame(event.data).catch(() => { if(relay === current) end("Image invalide."); });
    };
    current.onclose = () => { if(relay === current) end("Session terminée. Une nouvelle autorisation sera nécessaire."); };
    current.onerror = () => { if(relay === current) end("Connexion au relais impossible."); };
}
$("connect").onclick = () => {
    if(!control || control.readyState !== WebSocket.OPEN || pairing) return;
    selected = $("nodes").value; if(!validNode(selected) || !canConnect(devices.get(selected))) return;
    if (requestedNode && selected !== requestedNode) return;
    $("nodes").disabled = true;
    consoleUI?.start(); consoleUI?.state('requested'); consoleUI?.device(devices.get(selected));
    pairing = true; $("connect").disabled = true; $("stop").disabled = false; metrics = {version:"0.4.0",stage:"connecting",frames:0,bytes:0};
    status("Demande de session…"); control.send(JSON.stringify({action:"authcookie"}));
    deadline = setTimeout(() => end("Délai de connexion ou d’autorisation dépassé.",'timeout'),90000);
};
$("stop").onclick = () => end("Session arrêtée par le technicien.",'stopped');
$("send").onclick = () => {
    const text = $("chat").value.trim(); if(!ready || !text || utf8.encode(text).length > 1024) return;
    send("chat",{text}); log(text,true); $("chat").value = "";
};
$("capture").onclick = () => { if(!screenHidden && send("captureRequest")) consoleUI?.event('capture_requested'); };
$("guideStart").onclick = () => {
    if (!guideSupported || guideActive()) return;
    const steps = $("guidePlan").value.split(/\r?\n/).map(text=>text.trim()).filter(Boolean);
    if (!steps.length || steps.length > 20 || steps.some(text=>utf8.encode(text).length > 800)) {
        $("guideStatus").textContent = "Saisissez 1 à 20 lignes non vides, de 800 octets UTF-8 maximum chacune."; return;
    }
    guide = {id:crypto.randomUUID(),steps,index:0,status:"idle",pending:null};
    $("guideNextText").value = steps[0]; renderGuide(); dispatchGuideStep();
};
$("guideNext").onclick = dispatchGuideStep;
$("guideStop").onclick = () => {
    if (!guideActive()) return;
    send("guideStop",{id:guide.id}); guide.status = "stopped"; guide.pending = null; renderGuide();
    consoleUI?.event('guide_stopped',{step:guide.index,total:guide.steps.length});
};
$("accept").onclick = () => {
    if(!incoming || incoming.bytes) return;
    incoming.bytes = new Uint8Array(incoming.size); incoming.updated = performance.now();
    transferStatus('incoming', 'Transfert accepté — attente des données', 0, incoming.size);
    $("accept").hidden = $("reject").hidden = true; send("ack",{id:incoming.id,offset:0});
};
$("reject").onclick = () => {
    if(incoming) send("cancel",{id:incoming.id,reason:'rejected'}); incoming = null;
    transferStatus('incoming', 'Transfert refusé par vous.');
    $("accept").hidden = $("reject").hidden = true; $("offer").textContent = "";
};
$("cancelTransfer").onclick = () => {
    if(incoming) send("cancel",{id:incoming.id});
    if(outgoing) send("cancel",{id:outgoing.id});
    incoming = outgoing = null; $("accept").hidden = $("reject").hidden = true; $("offer").textContent = "";
    $("transfer").textContent = "Transferts annulés.";
    transferStatus('incoming', 'Transfert annulé.'); transferStatus('outgoing', 'Transfert annulé.');
};
$("file").onchange = async () => {
    const file = $("file").files[0]; $("file").value = "";
    if(!ready || !file || outgoing) return;
    if(!validName(file.name) || file.size < 1 || file.size > MAX) { $("transfer").textContent = "Nom invalide ou fichier supérieur à 2 Mio."; return; }
    const epoch = frameEpoch;
    outgoing = { id:crypto.randomUUID(),awaiting:0,updated:performance.now(),bytes:new Uint8Array(0) };
    const item = outgoing;
    transferStatus('outgoing', 'Lecture du document…');
    try {
        const bytes = new Uint8Array(await file.arrayBuffer()), digest = await hash(bytes);
        if(epoch !== frameEpoch || outgoing !== item || !ready) return;
        item.bytes = bytes;
        send("offer",{id:item.id,name:file.name,size:bytes.length,kind:"document",sha256:digest});
        $("transfer").textContent = "Attente de l’acceptation sur l’appareil…";
        transferStatus('outgoing', 'Document proposé — attente de l’acceptation.');
    } catch {
        if(epoch !== frameEpoch || outgoing !== item) return;
        outgoing = null; $("transfer").textContent = "Lecture du document impossible.";
        transferStatus('outgoing', 'Lecture du document impossible.');
    }
};
$("download").onclick = () => { if(received) download(received.bytes,received.name); received = null; $("download").hidden = true; };
$("diagnostic").onclick = () => download(JSON.stringify(metrics,null,2),"meshcentral-diagnostic-technicien.json","application/json");
$("undo").onclick = () => { strokes.pop(); redraw(); };
$("annotate").onclick = () => {
    const value = strokes.filter(s => s.points.length >= 2);
    if(snapshotID && value.length) send("annotations",{id:snapshotID,strokes:value});
};
function point(event) {
    const rect = annotation.getBoundingClientRect();
    return [Math.max(0,Math.min(1,(event.clientX-rect.left)/rect.width)),Math.max(0,Math.min(1,(event.clientY-rect.top)/rect.height))].map(n=>Math.round(n*10000)/10000);
}
annotation.onpointerdown = event => {
    if(!snapshotID || strokes.length >= 32 || strokes.reduce((n,s)=>n+s.points.length,0) >= 510) return;
    annotation.setPointerCapture(event.pointerId); currentStroke = {points:[point(event)]}; strokes.push(currentStroke);
};
annotation.onpointermove = event => {
    if(!currentStroke || strokes.reduce((n,s)=>n+s.points.length,0) >= 512) return;
    currentStroke.points.push(point(event)); redraw();
};
annotation.onpointerup = annotation.onpointercancel = () => { currentStroke = null; };
setInterval(() => {
    if (ready) {
        const now = performance.now();
        consoleUI?.diagnostics(metrics,now-telemetryAt);
        if (!screenHidden) consoleUI?.freshness(now-(shownFrameAt || firstReadyAt), now-telemetryAt, shownFrameAt > 0);
    }
    if (guide?.pending && performance.now() - guide.pending.sentAt > 15000) {
        // Do not resend an uncertain step or infer completion from a timeout.
        $("guideStatus").textContent = "Confirmation de réception absente. Attendez ou arrêtez le guidage avant de recommencer.";
    }
    for(const item of [incoming,outgoing]) if(item && performance.now()-item.updated > 60000) {
        send("cancel",{id:item.id,reason:'timeout'});
        transferStatus(item === incoming ? 'incoming' : 'outgoing', 'Délai de transfert dépassé.');
        if(item === incoming) { incoming = null; $("accept").hidden = $("reject").hidden = true; $("offer").textContent = ""; }
        else outgoing = null;
        $("transfer").textContent = "Délai de transfert dépassé.";
    }
},1000);
consoleUI = new IOSConsole({$: $, download, canChangePlan:()=>!guideActive(), applyPlan:text=>{$("guidePlan").value=text;}});
function refreshDeviceList() {
    const choice = pairing ? selected : (requestedNode || $("nodes").value);
    $("nodes").replaceChildren();
    for (const node of devices.values()) {
        if (requestedNode && node._id !== requestedNode) continue;
        const option=document.createElement('option'); option.value=node._id;
        option.textContent=String(node.name||'Appareil').slice(0,128) + ((node.conn&1)?' — connecté':' — hors ligne'); $("nodes").appendChild(option);
    }
    if (devices.has(choice)) $("nodes").value=choice;
    else if (requestedNode) $("nodes").value='';
    const node=devices.get($("nodes").value); consoleUI.device(node);
    $("nodes").disabled=pairing || !!requestedNode;
    $("connect").disabled=pairing || !canConnect(node) || control?.readyState !== WebSocket.OPEN;
    if (pairing && (!devices.has(selected) || !(devices.get(selected).conn&1))) end('Appareil déconnecté ou accès retiré. Redémarrez la diffusion avant de demander une nouvelle session.');
    if (!pairing) consoleUI.state(node && (node.conn&1) ? 'available' : 'offline');
}
$("nodes").onchange=()=>refreshDeviceList();
$("refreshDevices").onclick=()=>{if(control?.readyState===WebSocket.OPEN)control.send(JSON.stringify({action:'nodes'}));};
$("fullscreen").onclick=()=>{ if(!screenHidden && screen.requestFullscreen) screen.requestFullscreen().catch(()=>status('Plein écran indisponible dans ce navigateur.')); };
$("screenScale").onchange=()=>{screen.className=$("screenScale").value==='actual'?'actual':'';};
window.addEventListener('message',event=>{
    if (window.parent === window || event.source !== window.parent || event.origin !== location.origin) return;
    if (event.data?.type==='meshcentral-ios-host' && event.data.action==='leave' && pairing) end('Session arrêtée : vous avez quitté la fiche d’assistance.','page_left');
});
window.addEventListener("pagehide",()=>{ end("Page fermée.",'page_left'); control?.close(); });
if(location.protocol !== "https:") status("Ouvrez cette page sur votre serveur MeshCentral en HTTPS.");
else {
    control = new WebSocket(url("control.ashx",{}));
    control.onopen = () => control.send(JSON.stringify({action:"nodes"}));
    control.onmessage = event => {
        if(typeof event.data !== "string" || event.data.length > 4*1024*1024) return;
        let value; try { value = JSON.parse(event.data); } catch { return; }
        if (!value || typeof value!=='object' || Array.isArray(value)) return;
        if(value.action === "nodes" && value.nodes) {
            devices.clear();
            for(const nodes of Object.values(value.nodes)) if(Array.isArray(nodes)) for(const node of nodes) {
                if(validNode(node?._id) && isIOS(node)) devices.set(node._id,node);
            }
            refreshDeviceList();
            if (!pairing) status(requestedNode && !devices.has(requestedNode) ? 'Cet appareil iOS n’est pas accessible avec votre session MeshCentral.' : 'Démarrez la diffusion sur l’appareil, puis demandez une session.');
        }
        if (value.action === 'event' && value.event) {
            const event=value.event;
            if (event.action==='nodeconnect' && devices.has(event.nodeid)) devices.get(event.nodeid).conn=Number.isInteger(event.conn)?event.conn:0;
            else if (event.action==='removenode') devices.delete(event.nodeid);
            else if (['addnode','changenode'].includes(event.action) && validNode(event.node?._id)) {
                const previous=devices.get(event.node._id);
                const next={...previous,...event.node,conn:event.node.conn ?? previous?.conn ?? 0};
                if (isIOS(next)) devices.set(event.node._id,next);
                else devices.delete(event.node._id);
            } else return;
            refreshDeviceList();
        }
        if(value.action === "authcookie" && pairing && typeof value.cookie === "string" && typeof value.rcookie === "string") {
            cookie = value.cookie; rcookie = value.rcookie; startRelay();
        }
    };
    control.onclose = () => end("Connexion MeshCentral fermée. Connectez-vous au serveur dans ce navigateur, puis rechargez cette page.");
    control.onerror = () => end("Connexion MeshCentral impossible. Vérifiez HTTPS et votre session.");
}
