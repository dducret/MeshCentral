// SPDX-License-Identifier: Apache-2.0
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { setTimeout: delay } = require('node:timers/promises');

const manifest = require('./migration.json');
const gitUrl = 'https://github.com/Ylianst/MeshCentral.git';
const shortRevision = manifest.upstream.slice(0, 8);
const releaseMarker = '.meshcentral-migration.json';
const verifiedFiles = ['package-lock.json', 'meshcentral.js', 'meshuser.js', 'meshdevicefile.js', 'webserver.js',
    'views/default.handlebars', 'views/default-mobile.handlebars', 'views/default3.handlebars', 'views/default3-v2.handlebars'];

function run(command, args, options = {}) {
    const result = spawnSync(command, args, {
        cwd: options.cwd, env: options.env, encoding: 'utf8', windowsHide: true,
        stdio: options.capture ? ['ignore', 'pipe', 'pipe'] : 'inherit'
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw Error(command + ' (' + args[0] + ') a échoué' + (result.stderr ? ' : ' + result.stderr.trim() : '.'));
    return options.capture ? result.stdout.trim() : undefined;
}

function npm(args, cwd) {
    const bin = path.dirname(process.execPath);
    const bundled = ['../lib/node_modules/npm/bin/npm-cli.js', 'node_modules/npm/bin/npm-cli.js']
        .map(file => path.resolve(bin, file)).find(file => fs.existsSync(file));
    if (bundled) return run(process.execPath, [bundled, ...args], { cwd });
    return run('npm', args, { cwd });
}

function sha(data) { return createHash('sha256').update(data).digest('hex'); }

function fileHashes(root, files) {
    return Object.fromEntries(files.map(file => [file, sha(fs.readFileSync(path.join(root, file)))]));
}

function checkNode() {
    const [major, minor, patch] = process.versions.node.split('.').map(Number);
    if (major < 22 || (major === 22 && (minor < 21 || (minor === 21 && patch < 1)))) {
        throw Error('Node.js >= 22.21.1 requis. Utiliser MC_NODE pour indiquer le Node du service.');
    }
}

function locations() {
    const app = path.resolve(process.env.MC_APP || '/opt/meshcentral/node_modules/meshcentral');
    const modules = path.dirname(app);
    if (path.basename(app) !== 'meshcentral' || path.basename(modules) !== 'node_modules') {
        throw Error('MC_APP doit pointer vers le dossier node_modules/meshcentral du service.');
    }
    const root = path.dirname(modules);
    return {
        app, modules,
        data: path.resolve(process.env.MC_DATA || path.join(root, 'meshcentral-data')),
        lot: path.resolve(process.env.MC_LOT || '/home/sdic'),
        staged: path.join(modules, '.meshcentral-ready-' + shortRevision),
        previous: path.join(modules, '.meshcentral-before-' + shortRevision),
        snapshots: path.join(root, 'migration-backups'),
        lock: path.join(modules, '.meshcentral-migration.lock')
    };
}

function checkInstallation(at) {
    if (!fs.lstatSync(at.app).isDirectory()) throw Error('Le dossier actif doit être un répertoire réel.');
    const info = JSON.parse(fs.readFileSync(path.join(at.app, 'package.json'), 'utf8'));
    if (info.name !== 'meshcentral' || info.version !== '1.3.1') throw Error('Installation MeshCentral 1.3.1 attendue.');
    if (!fs.statSync(path.join(at.data, 'config.json')).isFile()) throw Error('Indiquer le répertoire de données actif avec MC_DATA.');
}

function verifyOverlay(root) {
    const source = path.join(root, 'web-ui-v2');
    for (const file of manifest.overlayFiles) {
        const name = path.join(source, file.path);
        if (!fs.existsSync(name) || sha(fs.readFileSync(name, 'utf8').replace(/\r\n/g, '\n')) !== file.sha256) {
            throw Error('Source de la surcouche différente : ' + name + '. Indiquer avec MC_LOT une copie du lot ' + manifest.overlay.slice(0, 8) + '.');
        }
    }
    return path.join(source, 'prepare.cjs');
}

function verifyPrepared(app) {
    const marker = JSON.parse(fs.readFileSync(path.join(app, releaseMarker), 'utf8'));
    if (marker.upstream !== manifest.upstream || marker.overlay !== manifest.overlay ||
        JSON.stringify(marker.files) !== JSON.stringify(fileHashes(app, verifiedFiles))) {
        throw Error('La copie préparée a changé. Repartir d’une préparation vérifiée.');
    }
}

function requestedLanguages() {
    const languages = [...new Set((process.env.MC_LANGS || '').split(',').map(x => x.trim()).filter(Boolean))];
    if (languages.some(x => !/^[a-z0-9-]+$/.test(x))) throw Error('MC_LANGS attend des codes comme fr ou fr,de.');
    return languages;
}

function translate(app, languages) {
    if (!languages.length) return;
    const tool = path.join(app, 'translate', 'translate.js');
    const dictionary = path.join(app, 'translate', 'translate.json');
    const pages = ['default', 'default-mobile', 'default3', 'default3-v2', 'login', 'login2', 'login-mobile'];
    const start = 'require(process.argv[1]).startEx(process.argv).catch(e => { console.error(e.message); process.exitCode=1; });';
    for (const lang of languages) {
        const files = pages.map(page => path.join(app, 'views', page + '.handlebars'));
        run(process.execPath, ['-e', start, tool, 'translate', lang, dictionary, ...files, '--subdir:translations']);
        for (const page of pages) {
            const file = path.join(app, 'views', 'translations', page + '_' + lang + '.handlebars');
            if (!fs.existsSync(file)) throw Error('Traduction attendue : ' + file);
        }
    }
}

function fixModuleResolution(app) {
    const patch = path.join(__dirname, 'node-module-resolution.patch');
    const options = { cwd: app, env: { ...process.env, GIT_CEILING_DIRECTORIES: path.dirname(app) } };
    run('git', ['apply', '--check', patch], options);
    run('git', ['apply', patch], options);
}

function prepare(at, overlay, languages) {
    if (fs.existsSync(at.previous)) throw Error('Une bascule existe déjà. Utiliser la procédure de retour arrière au besoin.');
    if (fs.existsSync(at.staged)) {
        verifyPrepared(at.staged);
        console.log('Copie prête : ' + at.staged);
        return;
    }
    const work = fs.mkdtempSync(path.join(at.modules, '.meshcentral-prepare-'));
    try {
        const repo = path.join(work, 'source');
        const app = path.join(work, 'runtime');
        const archive = path.join(work, 'source.tar');
        fs.mkdirSync(app);
        run('git', ['init', '--quiet', repo]);
        run('git', ['-C', repo, 'fetch', '--no-tags', '--depth=1', gitUrl, manifest.upstream]);
        const fetched = run('git', ['-C', repo, 'rev-parse', 'FETCH_HEAD'], { capture: true });
        if (fetched !== manifest.upstream) throw Error('La révision officielle récupérée diffère de la révision attendue.');
        run('git', ['-C', repo, 'archive', '--format=tar', '--output=' + archive, fetched]);
        run('tar', ['-xf', archive, '-C', app]);

        run(process.execPath, [overlay, app, '--check']);
        npm(['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], app);
        fixModuleResolution(app);
        run(process.execPath, [overlay, app]);
        translate(app, languages);
        run(process.execPath, ['--check', path.join(app, 'meshcentral.js')]);
        run(process.execPath, ['--check', path.join(app, 'webserver.js')]);
        run(process.execPath, [overlay, app, '--check']);
        fs.writeFileSync(path.join(app, releaseMarker), JSON.stringify({
            upstream: fetched, overlay: manifest.overlay, languages, files: fileHashes(app, verifiedFiles)
        }, null, 2) + '\n');

        fs.chmodSync(app, fs.statSync(at.app).mode & 0o777);
        fs.renameSync(app, at.staged);
        console.log('Copie prête : ' + at.staged);
    } finally {
        fs.rmSync(work, { recursive: true, force: true });
    }
}

function systemd(app) {
    const service = process.env.MC_SERVICE || 'meshcentral.service';
    if (!/^[a-zA-Z0-9_][a-zA-Z0-9_.@:-]*$/.test(service)) throw Error('Nom d’unité systemd invalide.');
    const startCommand = run('systemctl', ['show', '--property=ExecStart', '--value', service], { capture: true });
    if (!startCommand.includes(path.join(app, 'meshcentral'))) {
        throw Error('ExecStart ne pointe pas vers le paquet ciblé. Vérifier MC_SERVICE et MC_APP.');
    }
    return {
        stop: () => run('systemctl', ['stop', service]),
        start: () => run('systemctl', ['start', service]),
        async wait() {
            let stable = 0;
            let pid;
            for (let attempt = 0; attempt < 45; attempt++) {
                const status = run('systemctl', ['show', '--property=ActiveState,MainPID', service], { capture: true });
                const current = /^MainPID=(\d+)$/m.exec(status)?.[1];
                if (/^ActiveState=active$/m.test(status) && current && current !== '0') {
                    stable = current === pid ? stable + 1 : 1;
                    if (stable >= 5) return;
                } else { stable = 0; }
                pid = current;
                await delay(1000);
            }
            throw Error('Le service MeshCentral ne reste pas actif.');
        }
    };
}

function snapshot(at) {
    fs.mkdirSync(at.snapshots, { recursive: true, mode: 0o700 });
    const data = fs.realpathSync(at.data);
    const target = fs.realpathSync(at.snapshots);
    const relative = path.relative(data, target);
    if (relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) {
        throw Error('Le répertoire de sauvegarde doit être extérieur aux données MeshCentral.');
    }
    const backup = fs.mkdtempSync(path.join(target, shortRevision + '-'));
    run('cp', ['-a', data, path.join(backup, 'data')]);
    console.log('Sauvegarde locale des données : ' + backup);
}

async function swapRelease({ app, candidate, saved, service, saveData }) {
    if (!fs.lstatSync(candidate).isDirectory() || fs.existsSync(saved)) throw Error('Emplacements de bascule indisponibles.');
    service.stop();
    let savedActive = false;
    let promoted = false;
    try {
        saveData();
        fs.renameSync(app, saved);
        savedActive = true;
        fs.renameSync(candidate, app);
        promoted = true;
        service.start();
        await service.wait();
    } catch (error) {
        try {
            if (promoted) {
                service.stop();
                fs.renameSync(app, candidate);
            }
            if (savedActive) fs.renameSync(saved, app);
            service.start();
            await service.wait();
        } catch (rollbackError) {
            throw Error(error.message + ' Restauration automatique incomplète : ' + rollbackError.message + ' Code précédent : ' + saved);
        }
        throw Error(error.message + ' Le code précédent a été remis en service.');
    }
}

async function main() {
    const args = process.argv.slice(2);
    const mode = args[0] || '--check';
    if (args.length > 1 || !['--check', '--prepare', '--activate', '--rollback'].includes(mode)) {
        throw Error('Usage : sh update.sh [--check|--prepare|--activate|--rollback]');
    }
    checkNode();
    const at = locations();
    checkInstallation(mode === '--rollback' ? { ...at, app: at.previous } : at);
    if (mode === '--check') {
        verifyOverlay(at.lot);
        run('git', ['--version']);
        run('tar', ['--version'], { capture: true });
        npm(['--version'], at.modules);
        if (fs.existsSync(at.staged)) verifyPrepared(at.staged);
        console.log('Contrôle OK pour ' + shortRevision + '. Paquet : ' + at.app + '. Données : ' + at.data);
        return;
    }

    fs.mkdirSync(at.lock);
    try {
        if (mode === '--prepare') {
            prepare(at, verifyOverlay(at.lot), requestedLanguages());
            return;
        }
        if (process.platform !== 'linux') throw Error('La bascule du service systemd s’exécute sur le serveur Linux.');
        const activating = mode === '--activate';
        if (activating) verifyPrepared(at.staged);
        await swapRelease({
            app: at.app, candidate: activating ? at.staged : at.previous,
            saved: activating ? at.previous : at.staged,
            service: systemd(at.app), saveData: () => snapshot(at)
        });
        console.log(activating ? 'Code ' + shortRevision + ' actif. Code précédent : ' + at.previous : 'Ancien code MeshCentral remis en service.');
    } finally {
        fs.rmdirSync(at.lock);
    }
}

module.exports = { swapRelease };
if (require.main === module) {
    main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
