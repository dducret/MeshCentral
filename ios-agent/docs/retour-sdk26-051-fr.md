<!-- SPDX-License-Identifier: Apache-2.0 -->
# MeshCentral 0.5.1 avec Xcode 26 et ReplayKit

Ce correctif rétablit le partage ReplayKit de la livraison 0.5.0. L’écran
de séance, **Masquer mon écran**, le chat, le microphone et **Reprendre le son**
sont disponibles comme en 0.5.0. La version de l’app et de l’extension est
0.5.1. Le choix de Xcode 26 concerne le SDK de compilation. La cible minimale
du projet reste iOS 16. [Versions de Xcode et SDK Apple](https://developer.apple.com/xcode/system-requirements/)

## Si vous avez déjà importé la 0.5.1 ScreenCaptureKit

1. Fusionnez le contenu de `MeshCentral-iOS-0.5.1-sdk26-rollback.zip` dans le
   projet contenant `Cargo.toml` et `apple/`. Le ZIP a pour référence la
   livraison `MeshCentral-iOS-0.5.1-screencapturekit-update.zip`. Les deux
   manifestes donnent les chemins et empreintes. Aucun fichier à supprimer ni
   à renommer.
2. Dans la **cible app MeshCentralIOS**, retirez la paire `-weak_framework`
   et `ScreenCaptureKit` ajoutée dans **Build Settings → Other Linker Flags**,
   en Debug et Release. Si vous avez utilisé **Link Binary With Libraries**,
   retirez l’entrée **ScreenCaptureKit.framework**. Conservez les autres
   arguments et frameworks.
3. Dans **Signing & Capabilities → Background Modes** de cette même cible,
   décochez **Screen Capture** si l’option apparaît. Si le projet gère le
   plist à la main, retirez seulement `screen-capture` de `UIBackgroundModes`.
   Gardez `audio` et vos autres réglages. Le correctif laisse en place vos
   fichiers de projet et de configuration.
4. Ouvrez le projet avec **Xcode 26.x** et sélectionnez **iOS** comme **Base SDK**
   dans les réglages de build. Réglez **Version** sur **0.5.1** et choisissez le
   même nouveau **Build** sur l’app et l’extension. Conservez Team, Bundle IDs,
   App Groups, groupes de trousseau et profils.
5. Faites **Clean Build Folder** et compilez en **Release**. La phase standard
   peut reconstruire Rust **0.4.5**. Si vous liez le framework manuellement,
   utilisez le framework Rust 0.4.5 de la 0.5.0. Le panneau web de la 0.5.0
   fournit l’état de masquage au technicien.

## Si vous êtes encore en 0.5.0

Compilez directement votre projet 0.5.0 dans Xcode 26. Cette livraison contient
déjà le partage ReplayKit et les commandes de séance. Si vous avez seulement
appliqué certains réglages de la notice ScreenCaptureKit, retirez les entrées
concernées aux étapes 2 et 3. [Guide de la 0.5.0](seance-050-fr.md)

## Vérifier le build et la séance

1. Dans le Terminal du Mac, `xcodebuild -version` et
   `xcrun --sdk iphoneos --show-sdk-version` permettent d’identifier le Xcode
   actif et le SDK iPhoneOS sélectionné.
2. Installez l’app et son extension Release du même Build. Préparez le partage,
   ouvrez le sélecteur et confirmez **Lancer la diffusion**. Dans MeshCentral,
   vérifiez la visualisation après l’accord de la personne assistée.
3. Acceptez une invitation **Chat** avec le micro. Vérifiez la voix dans les
   deux sens, le chat, puis le masque et le réaffichage de l’écran. Terminez
   depuis l’app, puis vérifiez l’arrêt de la diffusion et la nécessité d’un
   nouvel accord.

Les fichiers Swift de capture et de séance proviennent de la référence 0.5.0
vérifiée. Le relais annonce la version native 0.5.1. Le prototype
ScreenCaptureKit, qui exige le SDK 27, reste dans son archive d’origine.
[Disponibilité de ScreenCaptureKit sur iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)

Sous Windows, rustfmt, Clippy, les 52 tests Rust, les 11 cas WSS, les contrôles
du pont C, de MeshCentral et des licences passent. Les neuf tests de
configuration ReplayKit et la validation structurelle Xcode passent. La
structure du ZIP et sa fusion avec le candidat 0.5.1 ScreenCaptureKit sont
vérifiées. Le build Xcode 26, la signature Release et les essais sur appareil
restent à effectuer.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Branche distante
`master` à `6da4680a61cda2b610ceff28a3e4f0454b0e583c` lors de la vérification.
La lecture seule de `.git` a bloqué le fetch et la création de branche.
