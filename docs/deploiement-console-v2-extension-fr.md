<!-- SPDX-License-Identifier: Apache-2.0 -->

# Déployer et maintenir la console 2026 sur mc.sdic.ch

L’extension utilise les routes et les paramètres de l’instance MeshCentral.
La racine sert la console historique et `/v2` sert la console 2026. Les deux
adresses partagent le domaine, l’authentification, les droits, les préférences
et la connexion WebSocket de MeshCentral.

Le lot prend en charge le paquet npm officiel `meshcentral@1.3.1` et la
révision `7d52d950b6d066e7212d7831b87b5da9359651a5` du fork. La révision iOS
`43a25978` contient les mêmes fichiers source concernés que `7d52d950`.
Seul `webserver.js` reçoit un patch à l’installation. Le gabarit 2026 est
généré dans `views/default3-v2.handlebars`
à partir du gabarit Bootstrap de la version préparée. Les deux gabarits de
base, le schéma et l’exemple de configuration restent tels que livrés par
MeshCentral. Le lot utilise la licence Apache-2.0.

## 1. Préparer le code de la nouvelle instance

Sauvegarde le `config.json` actif et l’ancienne image ou le code en service.
Décompresse le ZIP dans un répertoire dédié. Les commandes ci-dessous
supposent que `MC_LOT` désigne le dossier décompressé et `MC_APP` une copie
de préparation de la révision MeshCentral à utiliser. Git et Node.js sont
nécessaires dans cette copie. Vérifie la version de Node.js déclarée dans
`engines.node` du `package.json` cible. Le paquet npm 1.3.1 déclare
Node.js 20.0.0 au minimum et la révision `7d52d950` déclare 22.21.1.

Si tu disposes de la branche `codex/web-v2-overlay`, utilise son checkout
comme `MC_LOT`. Il contient les fichiers de l’extension et le correctif
npm 1.3.1. Tu peux l’utiliser directement à la place des deux ZIP.

Pour une installation npm dans `/opt/meshcentral`, la racine du paquet est
normalement `/opt/meshcentral/node_modules/meshcentral`. Vérifie qu’elle
contient `webserver.js` et `views/default3.handlebars`. Le `package.json`
du répertoire d’installation indique les dépendances, tandis que celui
du paquet indique la version de MeshCentral.

```bash
export MC_LOT=/chemin/vers/le/lot
export MC_APP=/chemin/vers/le/code-de-preparation
node "$MC_LOT/web-ui-v2/prepare.cjs" "$MC_APP" --check &&
node "$MC_LOT/web-ui-v2/prepare.cjs" "$MC_APP"
```

Le premier appel vérifie le gabarit et sélectionne le patch serveur qui
correspond au code installé. Si un contexte upstream a changé, il indique
les patchs à revoir. Parmi les fichiers fournis par MeshCentral, seul
`webserver.js` est modifié par le second appel. Le module `server.cjs`, les
ressources statiques et le gabarit généré sont ajoutés à la copie.

Pour la mire de connexion, reprends le répertoire `web-ui-v2/` complet de
la branche. `prepare.cjs` applique aussi `webserver-login.patch`, y compris
sur un paquet où la console `/v2` est déjà installée. Ce patch charge la
feuille de style de la mire dans les gabarits MeshCentral servis à `/v2`.
Sur une instance qui a déjà la première mire, `prepare.cjs` sélectionne
`webserver-login-upgrade.patch` pour lui ajouter les libellés permanents.

Si le ZIP d’extension est déjà décompressé, extrais le correctif npm par-dessus
ce lot dans `MC_LOT`, puis relance `--check`. Le correctif met à jour les
points d’intégration et réutilise les ressources du lot d’extension.

Si l’instance précédente utilisait le premier ZIP, pars d’une copie propre
de sa révision upstream ou de la révision que tu souhaites déployer.
Les gabarits `default` et `default3` et leurs variantes doivent provenir de
cette copie. L’ancien `console-devices.css` est remplacé par
`console-v2-devices.css` dans le nouveau lot. Garde l’ancienne image ou copie
intacte tant que le retour arrière est nécessaire.

Si tu sers des variantes minifiées ou traduites, génère celles du seul
gabarit 2026 dans la copie de préparation avec les outils upstream.
La variante française sert notamment les libellés de filtre et les
compteurs de groupe au singulier et au pluriel.
Remplace `fr` par `'*'` pour générer toutes les langues du dictionnaire.

```bash
(
    cd "$MC_APP/translate" || exit 1
    node translate.js minify ../views/default3-v2.handlebars &&
    node translate.js translate fr translate.json ../views/default3-v2.handlebars --subdir:translations
)
```

Pour Docker, prépare le code avant de construire l’image. Utilise le
Dockerfile et les options déjà employés pour ton instance, puis donne un tag
distinct à la nouvelle image. Laisse les dépendances de traduction dans
l’environnement de préparation. Conserve les volumes existants et utilise
la nouvelle image dans le service Compose actuel.
[Guide Docker MeshCentral](https://raw.githubusercontent.com/Ylianst/MeshCentral/master/docker/README.md)

## 2. Activer les deux adresses

Dans le `config.json` actif, ajoute ou conserve `"webUiV2": true` dans
l’objet du domaine servi sur `mc.sdic.ch`, généralement `domains[""]`.
Conserve le reste de la configuration et les volumes, puis démarre le
service avec le code préparé ou la nouvelle image. Le proxy doit transmettre
`/`, `/v2` et `/v2/` à la même instance. Les ressources et `control.ashx`
continuent d’utiliser leurs chemins habituels. Le réglage MeshCentral
`rootRedirect`, s’il est configuré, s’applique aussi à l’entrée `/v2`.

Dans le même profil de navigateur et avec un compte restreint, contrôle
[la racine historique](https://mc.sdic.ch/) et
[la console 2026](https://mc.sdic.ch/v2). Vérifie la session partagée, les
droits, les filtres et le retour à la liste sur grand écran et sur mobile.
La [fiche de recette](recette-console-appareils-fr.md) précise les résultats
attendus.

## 3. Reprendre une mise à jour upstream

Garde `codex/web-v2-overlay` comme source du lot. Prépare la nouvelle
révision upstream ou le nouveau paquet npm dans une copie de déploiement
distincte, puis renseigne `MC_APP` avec cette nouvelle racine. Pour npm,
utilise le dossier `node_modules/meshcentral` de la nouvelle installation.
Applique de nouveau les deux commandes de la section 1 avec `MC_LOT`
pointant vers le checkout de la branche. Ce contrôle doit être rejoué
après chaque remplacement du paquet, car l’installation npm fournit son
propre `webserver.js`.

Si `prepare.cjs --check` échoue, adapte le patch serveur aux points
d’intégration ou `console-view.patch` au gabarit Bootstrap, selon le message,
puis consigne la nouvelle base vérifiée dans la fiche de recette. Après un
contrôle réussi, régénère la fiche et ses variantes dans la copie de
déploiement et rejoue la recette. Conserve `webUiV2` dans `domains[""]`
du `config.json` actif si ton instance utilise le domaine par défaut.

La branche conserve les sources de l’extension, ses patchs et la
documentation. La préparation produit `webserver.js` patché, le gabarit
généré et les ressources déployées dans la copie de déploiement.

Pour désactiver la route, retire l’option `webUiV2` et redémarre. Pour
annuler le déploiement du code, repasse sur l’image ou la copie sauvegardée.
Sur une copie de préparation, applique `git apply --reverse` d’abord à
`webserver-login.patch`, puis au patch serveur correspondant
(`webserver-npm-1.3.1.patch` pour le paquet npm officiel). Les fichiers
générés peuvent ensuite être retirés de cette copie.
