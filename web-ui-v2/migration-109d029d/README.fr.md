<!-- SPDX-License-Identifier: Apache-2.0 -->

# Migrer mc.sdic.ch vers MeshCentral 109d029d

Le lot prépare le commit officiel `109d029ded08606495a9c712102525a026269633` avec la surcouche `5059e99d`. Le numéro dans `package.json` reste 1.3.1. La révision exacte est enregistrée dans `.meshcentral-migration.json` dans le paquet déployé.

Le script récupère le commit officiel, installe son verrou de dépendances de production et prépare les gabarits à partir de ce code. Le patch de compatibilité npm permet au démarrage d’identifier le manifeste du module effectivement résolu par Node lorsque le module masque son fichier `package.json`. Le contrôle de la version exigée reste appliqué.

## Préparer sans arrêter le service

Exécute les commandes Linux depuis ce dossier. Le script utilise Git, tar, npm et Node.js 22.21.1 ou ultérieur. Aligne `MC_NODE` sur le Node du service si le shell choisit une autre version.

Par défaut, `MC_LOT=/home/sdic` désigne le dossier qui contient `web-ui-v2/`, `MC_APP=/opt/meshcentral/node_modules/meshcentral` désigne le paquet et `MC_DATA=/opt/meshcentral/meshcentral-data` désigne les données. `MC_SERVICE` vaut `meshcentral.service`.

Le lot installé ou une copie de son checkout doit correspondre à `5059e99d`. Si les sources du serveur sont plus anciennes, prépare une copie contenant les sources de ce commit. Le ZIP incrémental précédent `MeshCentral-Web-V2-Update-5059e99d.zip` fournit les deux fichiers à superposer au lot `61e00d10`. Indique cette copie avec `MC_LOT`.

```sh
sh ./update.sh --check
sh ./update.sh --prepare
```

Le commit officiel sert le gabarit source si sa variante minifiée est absente. Pour régénérer les vues françaises depuis le code sécurisé, indique `MC_LANGS=fr` dès la préparation. Si le traducteur MeshCentral est déjà installé dans un environnement distinct, fournis son `NODE_PATH` habituel.

```sh
MC_LANGS=fr sh ./update.sh --prepare
```

La préparation laisse le paquet en service à sa place et crée `.meshcentral-ready-109d029d` dans son dossier parent. Elle télécharge les sources et dépendances officielles. Le ZIP contient les scripts, leurs empreintes et le patch de migration sous Apache-2.0. Les binaires, les gabarits générés et les dépendances héritées sont obtenus ou produits sur place.

## Basculer pendant la fenêtre de maintenance

Le domaine actif conserve `"webUiV2": true` dans `domains[""]`. Avec des gabarits personnalisés dans `meshcentral-web*/views`, vérifie qu’ils reprennent les correctifs et sont compatibles avec la nouvelle base. MeshCentral peut les sélectionner à la place des gabarits préparés.

Le script vérifie l’`ExecStart` et arrête le service. Il copie le répertoire de données actif dans `/opt/meshcentral/migration-backups/`, met le paquet prêt au chemin actuel, puis relance l’unité. Le fichier de service, le chemin du paquet et la configuration sont conservés. Si la base est externe, sa sauvegarde relève du mécanisme de cette base.

```sh
sh ./update.sh --activate
```

Sur le même profil de navigateur, ouvre [l’interface historique](https://mc.sdic.ch/) et [la console /v2](https://mc.sdic.ch/v2/). Vérifie l’authentification, le groupe en lecture seule, la fiche et le retour à la liste. Vérifie aussi la remontée d’un agent Windows et Linux utilisé sur ce serveur. Un redémarrage peut nécessiter une reconnexion.

## Revenir au paquet précédent

Le code précédent est conservé sous `/opt/meshcentral/node_modules/.meshcentral-before-109d029d`. Un échec détecté au démarrage provoque une restauration automatique du code et une tentative de redémarrage. En cas de problème constaté après le démarrage, la commande suivante effectue la bascule inverse.

```sh
sh ./update.sh --rollback
```

Le retour de version conserve les données courantes. Le snapshot antérieur est disponible pour une restauration examinée séparément si la base en a besoin. Le dossier local du snapshot peut contenir des clés et des bases. Il reste protégé sur le serveur.
