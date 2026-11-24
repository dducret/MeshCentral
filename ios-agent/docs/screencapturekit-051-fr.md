<!-- SPDX-License-Identifier: Apache-2.0 -->
# Partage d’écran avec ScreenCaptureKit en 0.5.1

Cette notice s’applique au prototype SDK 27 archivé. Pour compiler avec
Xcode 26, utilisez le [correctif ReplayKit](retour-sdk26-051-fr.md).

Sur iPhone et iPad physiques sous iOS ou iPadOS 27 ou ultérieur, la séance
utilise le sélecteur système ScreenCaptureKit. L’app transmet la vidéo à la
visualisation MeshCentral existante. Le chat et le microphone continuent
de passer par l’invitation MeshMessenger. Sur les versions système plus
anciennes, le partage utilise l’extension ReplayKit. Le simulateur garde
la capture de la fenêtre de l’app. [Exemple ScreenCaptureKit d’Apple](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)

## Démarrer une séance

1. Dans MeshCentral sur le mobile, touchez **Préparer le partage d’écran**.
   La préparation dure au maximum deux minutes. Le technicien ouvre **Desktop**
   ou **Plugins → Assistance iOS → Demander une session**.
2. Sur le mobile, vérifiez le nom du technicien. Touchez **Choisir mon écran**,
   puis confirmez le partage dans le sélecteur d’iOS ou d’iPadOS. Si vous avez
   choisi la validation séparée dans les options, touchez d’abord **Autoriser
   cette assistance**. Confirmez avant l’expiration de la demande. Les images
   commencent après la confirmation du système.
3. Si vous souhaitez parler, demandez au technicien d’envoyer l’invitation
   **Chat**, puis acceptez l’utilisation du microphone. Vous pouvez utiliser
   **Masquer mon écran**, **Partager de nouveau mon écran** et **Terminer** comme
   en 0.5.0. Le masque suspend l’envoi vidéo pendant que le flux système et son
   indicateur restent actifs. [Parcours de la séance 0.5.0](seance-050-fr.md)

La séance de partage dure au maximum dix minutes à compter du démarrage
de la capture. L’annulation dans le sélecteur, l’arrêt ou la suspension du flux
par le système et la perte de la connexion demandent une nouvelle préparation
et un nouvel accord. Pendant la préparation, quitter l’app annule le partage.
Après le démarrage sur iOS ou iPadOS 27, le mode Screen Capture permet de
partager en changeant d’app. Le maintien du son suit l’accord audio de la
conversation et les interruptions du système. [Modes d’arrière-plan Apple](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)

## Appliquer le ZIP à la livraison 0.5.0

1. Partez du projet qui a reçu `MeshCentral-iOS-0.5.0-seance-update.zip`.
   Fusionnez le contenu de `MeshCentral-iOS-0.5.1-screencapturekit-update.zip`
   avec la racine contenant `Cargo.toml` et `apple/`. Les manifestes indiquent
   les fichiers modifiés et leurs empreintes. Aucun fichier à supprimer ni à
   renommer.
2. Ouvrez votre projet configuré avec **Xcode 27 ou ultérieur**. Dans les cibles
   **MeshCentralIOS** et **MeshCentralBroadcast**, réglez **Version** sur
   **0.5.1** et choisissez le même nouveau numéro de **Build**. Conservez vos
   réglages de signature, vos identifiants et vos groupes.
3. Dans la **cible MeshCentralIOS**, utilisez **Signing & Capabilities →
   Background Modes → Screen Capture**. Dans un plist géré manuellement, ajoutez
   uniquement `<string>screen-capture</string>` au tableau existant
   `UIBackgroundModes`. Gardez les valeurs déjà présentes, y compris `audio`.
4. Dans **Build Settings → Other Linker Flags** de cette même cible app,
   ajoutez les deux arguments `-weak_framework` et `ScreenCaptureKit` en
   Debug et Release. Conservez `$(inherited)` et les autres arguments. Si le
   framework est déjà dans **Link Binary With Libraries** avec le statut
   **Optional**, cette entrée suffit. La liaison optionnelle permet à l’app
   de se lancer sur les systèmes qui utilisent ReplayKit. [Liaison optionnelle Apple](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/WeakLinking.html)
5. Faites **Clean Build Folder** et installez les deux cibles en **Release**.
   La phase standard reconstruit le framework Rust **0.4.5**. Une intégration
   manuelle peut conserver le framework Rust 0.4.5 de la 0.5.0. Utilisez le
   panneau web 0.5.0 déjà installé, avec le plugin 0.1.0.

## Recette sur appareil

1. Sur un iPhone et un iPad physiques sous version 27 ou ultérieure, relevez le
   Build Release. Depuis le panneau, demandez une séance avant la préparation,
   puis avant la confirmation système. Vérifiez qu’aucune image ne parvient au
   technicien. Testez l’annulation du sélecteur, la validation séparée et
   l’expiration de la préparation. Chaque nouvel essai nécessite un nouvel accord.
2. Confirmez le partage. Vérifiez les images en portrait et en paysage, puis
   ouvrez Notes et Réglages. Vérifiez l’indicateur iOS et le rendu côté technicien.
   Effectuez un essai avec le panneau Assistance iOS et un autre avec Desktop.
   Vérifiez le comportement sur du contenu protégé par le système.
3. Acceptez un Chat avec le micro. Vérifiez les deux directions audio. Masquez,
   attendez **Écran masqué**, changez d’app puis revenez. Vérifiez que le
   technicien conserve le chat et observe une image masquée, puis qu’il reçoit
   une image fraîche quand la personne réaffiche l’écran.
4. Testez **Terminer**, l’arrêt système, le verrouillage, la coupure réseau et
   l’expiration. Vérifiez l’arrêt côté technicien et l’exigence d’un nouvel
   accord après chaque fin de séance. Mesurez le délai d’arrêt sur appareil.
5. Installez le même Build sur un appareil antérieur à la version 27.
   Vérifiez que l’app se lance, que le sélecteur ReplayKit fonctionne et que le
   chat, la voix et le masquage restent disponibles dans la séance autorisée.

## Implémentation et vérifications

Le chemin ScreenCaptureKit utilise la connexion authentifiée de l’app et la
même porte de consentement Rust que ReplayKit. Seul le bouton local peut
présenter le sélecteur. Le relais passe à l’état de partage après le démarrage
de `SCStream`. L’encodeur reçoit uniquement les images complètes, à trois
images par seconde au maximum, avec l’orientation signalée par le système.
L’encodeur et le relais réutilisent les bornes et le masque de la 0.5.0.
À la reprise, l’horloge du flux écarte les images prises sous le masque qui
étaient encore dans la file système.
L’adaptateur désactive le micro, le son système et la caméra dans
ScreenCaptureKit. Il n’ouvre aucun fichier ni accès aux Photos.
[Métadonnées des images Apple](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo)

La distribution reste soumise aux règles Apple sur le consentement, les
indicateurs de capture et l’usage des modes d’arrière-plan. Le ZIP contient
des sources Apache-2.0 et aucune copie du SDK. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Sous Windows, rustfmt, Clippy, les 52 tests Rust, les 11 scénarios WSS et les
contrôles du pont C, de MeshCentral et des licences passent. La validation
structurelle confirme le mode d’arrière-plan et la liaison optionnelle dans
la cible app. Les neuf tests de configuration ReplayKit passent. La compilation
avec le SDK Apple, la signature Release, XCTest et les essais sur appareil
restent à effectuer.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Branche distante
`master` à `6da4680a61cda2b610ceff28a3e4f0454b0e583c` lors de la vérification.
La lecture seule de `.git` a bloqué le fetch et la création de branche. Le ZIP
est comparé à l’archive de la 0.5.0 et à ses 158 empreintes de référence.
