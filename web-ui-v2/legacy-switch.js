// SPDX-License-Identifier: Apache-2.0
(function () {
    'use strict';

    if (typeof window.toggleBootstrapUIMode !== 'function' || typeof window.domainUrl !== 'string') return;
    window.toggleBootstrapUIMode = function () {
        if (window.xxdialogMode) return;
        const url = new URL(window.location.href);
        url.pathname = window.domainUrl + 'v2';
        url.searchParams.delete('sitestyle');
        window.location.assign(url);
    };
})();
