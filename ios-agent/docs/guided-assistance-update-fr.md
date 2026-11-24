<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installer le guidage et le démarrage rapide

Cette mise à jour s’applique à votre projet **0.3.0 déjà fonctionnel sur l’iPad**,
avec les correctifs TestFlight et `sharing-preflight-fix` précédemment livrés.
L’archive contient uniquement les sources modifiées ou nouvelles, avec leurs
chemins relatifs depuis le dossier contenant `Cargo.toml`, `apple` et `operator`.

## Sur le Mac

1. Faites une copie de sauvegarde de votre projet actuel, puis fermez Xcode.
2. Décompressez le ZIP dans un dossier temporaire. Copiez les fichiers inclus
   vers les mêmes emplacements dans votre projet existant, en fusionnant les
   sous-dossiers. **Ne remplacez pas les dossiers `apple`, `App` ou le projet
   entier** : ils contiennent des fichiers volontairement absents de ce ZIP.
   Avec Terminal, placez-vous dans le dossier décompressé puis utilisez :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Remplacez le chemin par celui du dossier contenant votre `Cargo.toml`.
   N’ajoutez pas `--delete`. Aucun fichier n’est à supprimer ou à renommer.
3. Rouvrez **votre** `apple/App/MeshCentralIOS.xcodeproj`. Aucun nouveau fichier
   Swift n’est à ajouter aux cibles : le guidage utilise les fichiers existants.
   Les sources Rust, le bridge et son en-tête doivent être copiés ensemble.
4. Choisissez **Product → Clean Build Folder**, puis compilez. Les phases
   existantes reconstruisent Rust pour l’app et l’extension. Exécutez aussi les
   tests avec **Product → Test** sur un simulateur.
5. Pour TestFlight, augmentez le numéro de **Build** en conservant la même valeur
   pour l’app et l’extension. Archivez et envoyez selon votre procédure habituelle,
   puis installez ce nouveau build sur l’iPad.

Aucun `.xcodeproj`, `Info.plist`, entitlement ou profil de signature n’est fourni.
Votre Team, vos Bundle IDs, App Groups, Keychain Groups et réglages sont conservés.
Ne relancez pas le générateur de projet pour cette mise à jour.

## Sur le serveur MeshCentral

Mettez à jour les trois fichiers `operator/ios-assist.html`, `ios-assist.js` et
`ios-assist.css` dans le dossier public personnalisé déjà utilisé. Les instructions
d’emplacement se trouvent dans `operator/README.md`. Si le panneau n’était pas
installé, suivez cette notice pour le dossier `meshcentral-web/public`.

Connectez-vous à MeshCentral puis ouvrez, dans le même navigateur :
**https://mc.sdic.ch/ios-assist.html**. Rechargez la page après copie.
Utilisez ce panneau pour le guidage, et fermez la session Bureau ordinaire :
une seule session d’assistance est prise en charge. Les handlers MeshCentral et
la base de données n’ont pas besoin d’être modifiés.

## Démarrer plus simplement

1. Sur l’iPad, touchez **Préparer et autoriser l’assistance**. Le texte indique
   que vous autorisez le premier technicien habilité sur votre serveur.
2. Touchez le bouton rond de diffusion, puis **Lancer la diffusion** dans la
   fenêtre iPadOS, dans les deux minutes.
3. Dans le panneau technicien, sélectionnez l’iPad et **Demander une session**.
   Le bouton **Autoriser cette assistance** n’est plus nécessaire dans ce mode.

Il reste donc une action de préparation dans notre app et la validation système
Apple : ce n’est pas un démarrage complet en un seul toucher. Pour choisir le
technicien après affichage de son identité, utilisez **Valider séparément
l’identité du technicien**. L’arrêt reste disponible, et la session dure dix
minutes au maximum. Chaque nouvelle diffusion nécessite un nouveau démarrage.

## Guider la personne

1. Sur l’iPad, ouvrez **Guidage, chat, documents, captures et diagnostic**.
2. Dans le panneau, saisissez une instruction par ligne, par exemple :

   ```text
   Ouvrez Réglages, puis revenez ici pour confirmer cette étape.
   Dans Réglages, touchez Wi-Fi, puis revenez ici pour confirmer.
   Vérifiez le nom du réseau connecté et indiquez-le dans le chat.
   ```

3. Cliquez **Démarrer le parcours**. La première étape apparaît dans l’app et
   dans l’historique du chat. L’utilisateur peut choisir **Étape terminée**,
   **J’ai besoin d’aide**, ou **Arrêter le guidage**.
4. Si la personne demande de l’aide, répondez dans le chat. Elle pourra ensuite
   confirmer l’étape. **Envoyer l’étape suivante** devient disponible seulement
   après sa confirmation. Vous pouvez ajuster le texte suivant avant son envoi.
5. Pour illustrer une étape, attendez que l’écran souhaité soit visible, puis
   **Demander une capture**. La personne revient dans l’app, vérifie l’aperçu
   figé, et choisit **Autoriser l’envoi de cette capture** ou **Refuser**.
6. Côté technicien, cliquez **Recevoir**, dessinez sur la capture, puis cochez
   **Joindre la capture… à l’étape à envoyer** avant d’envoyer l’étape. L’image
   et les traits sont attachés ensemble ; il n’est pas nécessaire de cliquer
   aussi sur **Envoyer les annotations**. La case se décoche après réception
   de l’étape pour éviter de réutiliser une image par erreur.

Une étape déjà envoyée est figée. Une nouvelle capture ou une annotation générale
ne modifie pas son illustration. Pour corriger une étape en cours, expliquez dans
le chat ou arrêtez le parcours puis commencez-en un nouveau.

Limites : 20 étapes, 800 octets UTF-8 par instruction ; 32 parcours par session.
Le compte technicien doit avoir le droit **Chat / Notify**. Le guidage fonctionne
dans notre app : l’utilisateur revient pour lire/répondre, puis effectue lui-même
les gestes dans les autres apps. Aucun contrôle tactile distant, superposition
sur Réglages ou notification en arrière-plan n’est ajouté.

Les tests portables ont été exécutés sur Windows. La compilation Xcode et les
nouveaux parcours sur iPad restent à vérifier sur votre matériel.

## Fichiers inclus (23)

```text
README-MAC.md
README.md
apple/App/Sources/AgentModel.swift
apple/App/Sources/AssistanceView.swift
apple/App/Sources/MeshCentralIOSApp.swift
apple/Broadcast/SampleHandler.swift
apple/Sources/MeshCentralAgent/Assistance.swift
apple/Sources/MeshCentralAgent/BroadcastChannel.swift
apple/Sources/MeshCentralAgent/DesktopRelay.swift
apple/Tests/MeshCentralAgentTests/AssistanceTests.swift
bridge/include/meshcentral_ios.h
bridge/src/lib.rs
docs/guided-assistance-update-fr.md
docs/guided-assistance.md
operator/README.md
operator/ios-assist.css
operator/ios-assist.html
operator/ios-assist.js
src/assistance.rs
tests/assistance.rs
tools/check-assistance.cjs
tools/check-desktop.cjs
tools/check-guidance-abi.py
```
