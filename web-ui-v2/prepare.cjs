// SPDX-License-Identifier: Apache-2.0
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function applyPatch(directory, name, ...options) {
    const patch = path.join(__dirname, name + '.patch');
    const input = fs.readFileSync(patch, 'utf8').replace(/\r\n/g, '\n');
    const env = { ...process.env, GIT_CEILING_DIRECTORIES: path.dirname(directory) };
    const result = spawnSync('git', ['apply', ...options, '-'], { cwd: directory, env, input, encoding: 'utf8' });
    if (result.error) throw result.error;
    return result;
}

function requireSuccess(result, message) {
    if (result.status !== 0) throw Error(message + '\n' + result.stderr.trim());
}

function generateView(source) {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'meshcentral-web-v2-'));
    const views = path.join(scratch, 'views');
    const template = path.join(views, 'default3.handlebars');
    try {
        fs.mkdirSync(views);
        fs.writeFileSync(template, fs.readFileSync(source, 'utf8').replace(/\r\n/g, '\n'));
        requireSuccess(applyPatch(scratch, 'console-view'), 'Le gabarit Bootstrap a changé. Revoir console-view.patch.');
        return fs.readFileSync(template);
    } finally {
        if (fs.existsSync(template)) fs.unlinkSync(template);
        if (fs.existsSync(views)) fs.rmdirSync(views);
        fs.rmdirSync(scratch);
    }
}

function selectServerPatch(app) {
    const patches = ['webserver', 'webserver-npm-1.3.1'];
    const failures = [];
    for (const name of patches) {
        const check = applyPatch(app, name, '--check', '--ignore-space-change');
        if (check.status === 0) return { name, applied: false };
        const reverse = applyPatch(app, name, '--check', '--reverse', '--ignore-space-change');
        if (reverse.status === 0) return { name, applied: true };
        failures.push(name + '.patch\n' + check.stderr.trim());
    }
    throw Error('Les points d’intégration serveur ont changé.\n' + failures.join('\n'));
}

function prepare(app, checkOnly) {
    const project = JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8'));
    if (project.name !== 'meshcentral') throw Error('Indiquer la racine de MeshCentral.');
    const views = path.join(app, 'views');
    const view = generateView(path.join(views, 'default3.handlebars'));
    const serverPatch = selectServerPatch(app);

    const assets = [
        ['server.cjs', 'web-ui-v2/server.cjs'],
        ['legacy-switch.js', 'public/scripts/console-v2-legacy-switch.js'],
        ['console-v2-devices.css', 'public/styles/console-v2-devices.css']
    ].map(([source, target]) => [path.join(app, target), fs.readFileSync(path.join(__dirname, source))]);
    const target = path.join(views, 'default3-v2.handlebars');
    const translations = path.join(views, 'translations');
    const variants = fs.existsSync(path.join(views, 'default3-v2-min.handlebars')) ||
        (fs.existsSync(translations) && fs.readdirSync(translations).some(name => /^default3-v2(?:-min)?_.*\.handlebars$/.test(name)));
    if (variants && (!fs.existsSync(target) || !fs.readFileSync(target).equals(view))) {
        throw Error('Des variantes 2026 existent. Régénérer le lot dans une préparation propre pour éviter de les resservir.');
    }

    if (checkOnly) return;
    for (const [file, contents] of assets) {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, contents);
    }
    fs.writeFileSync(target, view);
    if (!serverPatch.applied) requireSuccess(applyPatch(app, serverPatch.name, '--ignore-space-change'), 'Échec de l’application du patch serveur.');
}

try {
    const [directory, option, extra] = process.argv.slice(2);
    if (!directory || (option && option !== '--check') || extra) throw Error('Usage: node prepare.cjs <racine MeshCentral> [--check]');
    prepare(path.resolve(directory), option === '--check');
    console.log(option === '--check' ? 'Points d’intégration et gabarit compatibles.' : 'Console 2026 préparée.');
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
