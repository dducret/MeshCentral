/* SPDX-License-Identifier: Apache-2.0 */

(function () {
    'use strict';

    const form = document.getElementById('loginpanelform');
    if (!form) return; // Classic login layouts already show their field names beside the inputs.

    for (const id of ['username', 'password']) {
        const input = form.querySelector('#' + id);
        if (!input || input.labels.length) continue;
        const text = input.getAttribute('placeholder') || input.title;
        if (!text) continue;

        const label = document.createElement('label');
        label.className = 'console-login-label';
        label.htmlFor = id;
        label.textContent = text;
        input.before(label);
        input.removeAttribute('placeholder');
    }
})();
