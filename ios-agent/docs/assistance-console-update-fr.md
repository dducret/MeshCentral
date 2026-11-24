<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installer la console Assistance iOS

Ce complément s’applique **après**
`MeshCentral-iOS-0.3.0-guided-assistance-update.zip` (SHA-256 :
`3cdd11c3e9d20e92be86ca30423f9fde4fbcb0dd53c000022e683cbc8a1575d8`).
Si vous n’avez pas encore appliqué ce précédent complément, faites-le d’abord.
Ce ZIP contient seulement les fichiers modifiés ou nouveaux depuis cette base.

Il ajoute un plugin MeshCentral, les états de présence/session, cinq procédures
réutilisables et leur import/export, un compte rendu d’intervention avec inclusion
facultative des échanges, le plein écran et un diagnostic réseau enrichi.
Le chat, les captures annotées, les documents et le guidage existants restent
accessibles dans la même console. Le partage est toujours en lecture seule.

## 1. Mettre à jour le projet sur le Mac

1. Faites une sauvegarde de votre projet actuel et fermez Xcode.
2. Décompressez le nouveau ZIP dans un dossier temporaire. Dans Terminal,
   placez-vous dans ce dossier : il doit contenir `README-MAC.md`, `apple`,
   `bridge`, `src`, `operator` et `plugin`.
3. Fusionnez son contenu avec **le dossier de votre projet existant contenant
   `Cargo.toml`**, en adaptant le chemin :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   N’ajoutez pas `--delete`. Ne remplacez pas le dossier du projet dans Finder :
   l’archive ne contient volontairement pas les fichiers inchangés.
4. Rouvrez votre `apple/App/MeshCentralIOS.xcodeproj`, puis **Product → Clean
   Build Folder**. Compilez et exécutez les tests avec **Product → Test** sur un
   simulateur. Les phases existantes recompilent le cœur Rust pour l’app et
   l’extension ; les sources Rust, le bridge et l’en-tête doivent être copiés ensemble.
5. Pour TestFlight, augmentez le numéro **Build** de l’app et de l’extension à la
   même valeur, archivez puis envoyez selon votre procédure habituelle.

**Aucun `.xcodeproj`, `Info.plist`, entitlement, profil ou réglage de signature
n’est remplacé.** Aucun nouveau fichier Swift à ajouter aux cibles. Le framework
Apple Network est importé par une source existante, sans nouvelle capability.
Conservez votre Team, Bundle IDs, App Groups et Keychain Groups. Aucun fichier
n’est à supprimer ou renommer. Ne régénérez pas le projet Xcode.

## 2. Mettre à jour MeshCentral

1. Copiez ensemble les quatre fichiers `operator/ios-assist.html`,
   `ios-assist.css`, `ios-assist.js` et **`ios-console.js`** dans votre dossier
   public personnalisé déjà utilisé, généralement `meshcentral-web/public`.
   Conservez tous les autres fichiers. Détails : [notice du panneau](../operator/README.md).
2. Vérifiez la console indépendante à `https://mc.sdic.ch/ios-assist.html` après
   votre connexion normale à MeshCentral. Rechargez complètement la page.
3. Installez `plugin/iosAssistance` dans le dossier de données du serveur selon
   [la notice du plugin](../plugin/iosAssistance/README.md). Elle indique précisément
   comment fusionner la configuration sans désactiver vos autres plugins.
4. Redémarrez le service pour charger le plugin. Dans la fiche de l’iPad,
   ouvrez **Plugins → Assistance iOS**. L’iPad est présélectionné.

Le plugin 0.1.0 et la console `console-1` accompagnent l’agent 0.3.0. Il n’y a pas
de modification des handlers ou de la base MeshCentral. Aucun fichier de
configuration serveur complet n’est fourni. Rien n’a été déployé sur votre
serveur ni envoyé à Apple pendant cette tâche.

## 3. Faire un essai sur l’iPad

1. Installez le nouveau build. Préparez l’assistance et lancez la diffusion avec
   la validation iPadOS habituelle. Le démarrage rapide reste disponible ; la
   fenêtre système Apple ne peut pas être supprimée.
2. Dans la fiche MeshCentral, ouvrez le plugin et **Demander une session**.
   Vérifiez la présence « diffusion prête », puis « Assistance active » après
   autorisation. Fermez d’abord toute session Bureau/console déjà ouverte.
3. Ouvrez Réglages sur l’iPad. Le partage doit continuer. Revenez dans l’app
   pour répondre au chat ou confirmer les étapes : aucune surimpression interactive
   n’est injectée au-dessus des autres applications.
4. Dans **Bibliothèque de parcours**, chargez « Vérifier le Wi-Fi ». Adaptez les
   instructions, lancez le parcours et testez « J’ai besoin d’aide », puis « Étape
   terminée » sur l’iPad. Essayez une étape avec une capture annotée autorisée.
5. Mémorisez un modèle personnalisé, exportez puis réimportez la bibliothèque.
   Rien n’est sauvegardé automatiquement entre deux ouvertures de page.
6. Observez le réseau et les recommandations. Arrêtez la diffusion depuis l’iPad :
   l’image doit cesser et la connexion être fermée. Une session future nécessite
   une nouvelle autorisation ; aucun accord ancien n’est réutilisé.
7. Exportez le **compte rendu** avant de changer de fiche ou commencer une autre
   session. Par défaut, il exclut messages, instructions et notes. Cochez leur
   inclusion si vous souhaitez les conserver, puis utilisez **Effacer le compte
   rendu et les notes** pour vider la mémoire de la console.

Une coupure réseau peut empêcher la transmission du dernier diagnostic : la
console affiche alors la fermeture ou l’absence de télémétrie. Les mesures
n’établissent pas à elles seules la cause exacte d’une panne. Les fichiers de
diagnostic et de compte rendu sont deux exports distincts.

## Vérifications et limites de cette livraison

Exécuté sous Windows : 37 tests Rust, rustfmt, Clippy, ABI Rust chargée réellement,
tests Node du panneau, des imports/exports et de l’intégration du plugin via le
sérialiseur MeshCentral, contrôles de licences et de structure du projet.
Les détails et la révision de référence sont dans [le document technique](assistance-console.md).

Xcode, les XCTest, l’affichage dans un navigateur réel et la nouvelle connexion
sur iPad n’ont pas été exécutés ici. Le partage précédent a été confirmé par vous ;
cela ne valide pas encore les ajouts de ce complément. Aucun contrôle tactile,
MDM, conversation audio ou reprise automatique après coupure n’est annoncé.
Tout le nouveau code est Apache-2.0 ; aucune dépendance tierce n’a été ajoutée.

## Fichiers inclus

30 fichiers, chemins relatifs depuis la racine du projet :

```text
README-MAC.md
README.md
apple/App/Sources/AssistanceView.swift
apple/Broadcast/SampleHandler.swift
apple/Sources/MeshCentralAgent/Connection.swift
apple/Sources/MeshCentralAgent/ConnectionDiagnostics.swift
apple/Sources/MeshCentralAgent/DesktopRelay.swift
apple/Tests/MeshCentralAgentTests/AssistanceTests.swift
bridge/include/meshcentral_ios.h
bridge/src/lib.rs
docs/assistance-console-update-fr.md
docs/assistance-console.md
docs/licensing.md
operator/README.md
operator/ios-assist.css
operator/ios-assist.html
operator/ios-assist.js
operator/ios-console.js
plugin/iosAssistance/LICENSE
plugin/iosAssistance/README.md
plugin/iosAssistance/config.json
plugin/iosAssistance/iosAssistance.js
src/assistance.rs
tests/assistance.rs
tools/check-assistance.cjs
tools/check-console-session.cjs
tools/check-console.cjs
tools/check-guidance-abi.py
tools/check-licenses.cjs
tools/check-plugin.cjs
```
