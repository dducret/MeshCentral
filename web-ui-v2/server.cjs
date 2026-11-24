// SPDX-License-Identifier: Apache-2.0
'use strict';

function enabled(domain, reservedDomain) {
    return domain.webuiv2 === true && (domain.url !== '/' || !reservedDomain || reservedDomain.dns != null);
}

function registerRoutes(app, url, parseForm, handlers) {
    function serve(req, res, next) {
        const domain = handlers.getDomain(req);
        if (!domain || !handlers.isEnabled(domain)) return next();
        const route = domain.url + 'v2';
        if (req.path.replace(/\/$/, '').toLowerCase() !== route) return next();
        if (typeof domain.rootredirect === 'string') {
            return req.method === 'POST' ? next() : handlers.redirectRoot(req, res);
        }
        // Relative endpoints and assets resolve under the domain root at the canonical URL.
        if (req.path !== route) {
            res.set('Cache-Control', 'no-store');
            return res.redirect(307, route + handlers.queryPortion(req));
        }
        req.webUiV2 = true;
        return req.method === 'POST' ? handlers.postRoot(req, res) : handlers.getRoot(req, res);
    }

    app.route(url + 'v2').get(serve).post(parseForm, serve);
}

function rememberLogin(req) {
    if (!req.session) return;
    if (req.webUiV2 === true) req.session.webUiV2Login = true;
    else clearLogin(req);
}

function clearLogin(req) {
    if (req.session) delete req.session.webUiV2Login;
}

function returnFromLogin(req, domain, url, isEnabled, getBaseUrl) {
    if (!isEnabled || !req.session || req.session.webUiV2Login !== true || !req.session.userid) return url;
    clearLogin(req);
    if (url === domain.url || url.startsWith(domain.url + '?')) {
        return domain.url + 'v2' + url.substring(domain.url.length);
    }
    if (!getBaseUrl) return url;
    try {
        const base = new URL(getBaseUrl());
        const target = new URL(url, base);
        if (target.origin === base.origin && target.pathname === domain.url && !target.username && !target.password) {
            return domain.url + 'v2' + target.search;
        }
    } catch (error) {
        if (!(error instanceof TypeError)) throw error;
    }
    return url;
}

module.exports = { enabled, registerRoutes, rememberLogin, clearLogin, returnFromLogin };
