<!-- SPDX-License-Identifier: Apache-2.0 -->
# Plugin local Assistance iOS — 0.1.0

Ce plugin original Apache-2.0 ajoute **Assistance iOS** dans l’onglet **Plugins**
de la fiche d’un agent iOS/Rust. Il intègre la console existante avec l’appareil
présélectionné. Aucun paquet npm, endpoint privilégié, modification des fichiers
MeshCentral ou téléchargement automatique n’est nécessaire.

## Installation sur le serveur

1. Installez d’abord les **quatre fichiers web** selon
   [operator/README.md](../../operator/README.md) et vérifiez que `/ios-assist.html`
   s’ouvre après votre connexion normale à MeshCentral.
2. Repérez **le dossier de données réellement utilisé par votre service**,
   généralement `meshcentral-data` (il peut être configuré ailleurs). Copiez ce
   dossier `iosAssistance`, avec son contenu, dans :

   ```text
   meshcentral-data/plugins/iosAssistance/
       iosAssistance.js
       config.json
       LICENSE
       README.md
   ```

3. Sauvegardez le `config.json` de votre serveur. Si **aucun autre plugin n’est
   installé**, fusionnez cette propriété dans l’objet `settings` existant :

   ```json
   "plugins": {
     "enabled": true,
     "list": ["iosAssistance"]
   }
   ```

   Ce fragment ne remplace pas le fichier de configuration ni l’objet `settings`.
   Conservez les autres paramètres et les virgules nécessaires au JSON.

   **Si une liste `settings.plugins.list` existe déjà**, ajoutez `iosAssistance`
   sans retirer ses noms. **Si d’autres plugins sont gérés depuis l’interface et
   qu’il n’existe pas de liste**, ne collez pas ce fragment tel quel : le chargeur
   local de MeshCentral utilise cette liste à la place des plugins activés dans
   sa base. Relevez d’abord leurs `shortName` et incluez tous ceux à conserver,
   avec `iosAssistance`. Vous pouvez continuer à utiliser la console indépendante
   tant que cette configuration n’est pas prête.
4. Redémarrez MeshCentral avec votre procédure habituelle. Reconnectez ou rechargez
   le navigateur, ouvrez la fiche de l’iPad, puis **Plugins → Assistance iOS**.
   Pour mettre à jour ensuite ce plugin local, remplacez ses fichiers et redémarrez.

Le `config.json` livré ici décrit ce plugin ; **ce n’est pas** le `config.json`
du serveur. Il n’existe pas d’URL publique d’installation ou de mise à jour :
n’utilisez pas le bouton « Add plugin » avec une URL inventée.

## Comportement et limites

- L’iPad est reconnu par son identifiant expérimental ou le préfixe de son core.
  La console vérifie la sélection via le serveur authentifié ; une URL seule ne
  donne aucun droit. Les permissions habituelles et le consentement local restent
  indispensables.
- L’iframe reste intacte lors des rafraîchissements de la même fiche. Changer de
  fiche la détruit ; quitter la page Plugins arrête le relais. Un autre sous-onglet
  de plugin masque la console sans arrêter la session. L’iPad conserve son témoin
  et son bouton d’arrêt. Une seule session d’assistance est acceptée.
- Le lien d’ouverture séparée nécessite de terminer d’abord la session intégrée.
  Ne modifiez pas les protections de cookies ou HTTPS pour faire fonctionner
  l’intégration. Les quatre fichiers web doivent être sur la même origine et le
  même chemin de domaine MeshCentral.
- Si l’onglet manque, vérifiez le dossier de données, la casse `iosAssistance`,
  la liste des plugins et les journaux de démarrage du service. Si le panneau est
  vide, vérifiez d’abord son URL directe et les quatre fichiers web.

Validation locale : sérialisation réelle par `pluginHandler.js` et scénarios DOM
déterministes sur la révision `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Pas de déploiement serveur ni de validation visuelle du navigateur effectué ici.
L’interface par défaut a servi de référence ; vérifiez votre thème/version.
Le champ de compatibilité de la configuration ne certifie pas toutes les versions.

Référence : [hooks officiels MeshCentral](https://docs.meshcentral.com/meshcentral/plugins/).
