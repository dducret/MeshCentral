// SPDX-License-Identifier: Apache-2.0
'use strict';
// All exported functions are serialized by MeshCentral. Keep them self-contained.
module.exports.iosAssistance = function () {
    const obj = {};
    obj.exports = ['onWebUIStartupEnd', 'onDeviceRefreshEnd', 'goPageStart', 'goPageEnd', 'mount', 'syncVisibility'];
    obj.onWebUIStartupEnd = function () {
        const plugin = pluginHandler.iosAssistance;
        const headers = document.getElementById('p19headers');
        if (headers && !plugin.observer) {
            plugin.observer = new MutationObserver(function () { pluginHandler.iosAssistance.syncVisibility(); });
            plugin.observer.observe(headers, {subtree:true, childList:true, attributes:true, attributeFilter:['class']});
        }
    };
    obj.onDeviceRefreshEnd = function (nodeid) {
        const plugin = pluginHandler.iosAssistance;
        const node = typeof currentNode === 'object' ? currentNode : null;
        const supported = node && node._id === nodeid && node.agent &&
            (node.agent.id === 4294967280 || (typeof node.agent.core === 'string' && node.agent.core.startsWith('MeshCentral iOS Rust ')));
        if (plugin.node !== nodeid || !supported) {
            const old = document.getElementById('iosAssistanceHost');
            if (old) old.remove(); // unload closes the previous device's relay
            plugin.node = supported ? nodeid : null;
        }
        if (!supported) return;
        pluginHandler.registerPluginTab({tabId:'iosAssistanceTab', tabTitle:'Assistance iOS'});
        const tab = document.getElementById('iosAssistanceTab');
        if (tab) {
            const text = document.createElement('p');
            text.textContent = 'Agent iOS / Rust — écran, guidage, chat, documents et diagnostic.';
            tab.appendChild(text);
            const link = document.createElement('a');
            const address = new URL('ios-assist.html', location.href);
            address.search = ''; address.hash = new URLSearchParams({node:nodeid}).toString();
            link.href = address.href; link.target = '_blank'; link.rel = 'noopener';
            link.textContent = 'Ouvrir la console dans un onglet séparé (fermez d’abord la session intégrée).';
            tab.appendChild(link);
        }
        plugin.onWebUIStartupEnd();
        if (typeof xxcurrentView !== 'undefined' && xxcurrentView === 19) plugin.mount();
    };
    obj.mount = function () {
        const plugin = pluginHandler.iosAssistance;
        const page = document.getElementById('p19');
        if (!page || !plugin.node || !/^node\/[^/]*\/[^/?#\s]+$/.test(plugin.node)) return;
        let host = document.getElementById('iosAssistanceHost');
        if (!host) {
            host = document.createElement('div'); host.id = 'iosAssistanceHost';
            const frame = document.createElement('iframe'); frame.id = 'iosAssistanceFrame';
            frame.title = 'Console Assistance iOS'; frame.allow = 'fullscreen';
            frame.style.cssText = 'width:100%;height:80vh;min-height:640px;border:0';
            const address = new URL('ios-assist.html', location.href);
            address.search = ''; address.hash = new URLSearchParams({node:plugin.node, embedded:'1'}).toString();
            frame.src = address.href;
            host.appendChild(frame); page.appendChild(host);
        }
        plugin.syncVisibility();
    };
    obj.syncVisibility = function () {
        const host = document.getElementById('iosAssistanceHost');
        const tab = document.getElementById('p19ph-iosAssistanceTab');
        if (host) host.style.display = tab && tab.classList.contains('on') ? '' : 'none';
    };
    obj.goPageStart = function (page) {
        if (page === 19) return;
        const frame = document.getElementById('iosAssistanceFrame');
        if (frame && frame.contentWindow) frame.contentWindow.postMessage({type:'meshcentral-ios-host',action:'leave'}, location.origin);
    };
    obj.goPageEnd = function (page) { if (page === 19) pluginHandler.iosAssistance.mount(); };
    return obj;
};
