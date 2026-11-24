<!-- SPDX-License-Identifier: Apache-2.0 -->
# Appel d’assistance pendant l’utilisation d’une autre app — 0.4.7

La 0.4.6 ferme volontairement MeshMessenger au passage en arrière-plan. La
0.4.7 prépare un essai audio pour suivre une consigne dans une autre app pendant
un appel. L’option **Garder le son dans les autres apps** apparaît dans l’invitation
sur iPhone ou iPad physique à partir d’iOS/iPadOS 17.5.1, si le Build déclare le mode
audio. Le complément `MeshCentral-iOS-0.4.7-audio-par-defaut-update.zip` la
préselectionne à chaque invitation. La personne peut la décocher avant d’accepter.

Laissez l’option cochée et touchez **Accepter avec le micro** pour autoriser
l’appel à continuer lorsque vous changez d’app. Dans le chat, attendez
**Appel prêt pour le changement d’app** et vérifiez que chacun entend l’autre.
Le micro peut rester actif lors d’un changement d’app ou d’un verrouillage.
Pour mettre fin à l’appel, revenez dans MeshCentral et touchez **Terminer**.
Sans cette option ou si le son ne tient pas en arrière-plan, l’appel se ferme et
un nouvel appel exige une nouvelle invitation.

## Installer le candidat dans Xcode

1. Partez du projet 0.4.6 ayant reçu `MeshCentral-iOS-0.4.6-clavier-chat-update.zip`.
   Fusionnez les fichiers de `MeshCentral-iOS-0.4.7-audio-arriere-plan-update.zip`
   dans la racine du projet contenant `Cargo.toml` et `apple/`. Les empreintes et
   la liste sont dans `SHA256SUMS-0.4.7.json` et `release-0.4.7.json`. Aucun fichier
   à supprimer ni à renommer.
2. La phase Rust du projet Xcode standard compile les nouvelles sources
   **0.4.3** pour les deux cibles. Si votre projet utilise un `MeshCore.xcframework`
   lié manuellement, mettez de côté l’ancien framework et reconstruisez-le avec
   `sh apple/build-xcframework.sh` depuis la racine. Les binaires 0.4.2 ne
   connaissent pas le nouvel accord audio. Les cibles Rust Apple et les deux
   parcours sont détaillés dans [le guide de compilation](secure-connection.md).
3. Dans la **cible app MeshCentralIOS**, activez **Signing & Capabilities →
   Background Modes → Audio, AirPlay, and Picture in Picture**. Cela ajoute la
   valeur `audio` au tableau `UIBackgroundModes` de l’Info.plist de l’app.
   Fusionnez cette valeur avec le tableau existant s’il y en a un. Gardez
   `NSMicrophoneUsageDescription` et les paramètres de signature existants.
   Ce réglage concerne la cible app. Le mode Audio suffit pour cet essai.
4. Réglez **Version à 0.4.7** sur l’app et l’extension et prenez un nouveau
   **Build** commun. Gardez le projet Xcode configuré, Team, Bundle IDs, App Groups,
   trousseau et profils. Faites **Clean Build Folder** et installez en Release
   sur appareil physique. Le ZIP ne remplace pas le projet ni le plist configuré.

Si le candidat 0.4.7 est déjà appliqué, fusionnez seulement les fichiers du
complément `MeshCentral-iOS-0.4.7-audio-par-defaut-update.zip` à la même racine.
Gardez la version 0.4.7, choisissez un nouveau Build commun aux deux cibles et
recompilez. Le mode Audio et les sources Rust 0.4.3 du candidat restent requis.

## Vérifier avant d’utiliser avec les personnes assistées

1. Sur une nouvelle invitation compatible, vérifiez que l’option est cochée et
   que l’explication est visible avant l’acceptation. Décochez-la et vérifiez
   que passer à une autre app ferme l’appel. Refaites l’essai en cochant l’option
   mais en choisissant **Accepter sans micro**. Vérifiez le même résultat.
2. Sur une nouvelle invitation, laissez l’option cochée et acceptez avec le micro.
   Une fois le son confirmé, ouvrez
   Réglages ou Notes pendant 30 secondes. Parlez et écoutez des deux côtés,
   revenez à l’app et touchez **Terminer**. Vérifiez l’arrêt du son et l’extinction
   de l’indicateur microphone. Répétez avec un partage d’écran actif.
3. Quittez l’app avant que l’appel soit prêt. Vérifiez qu’il se ferme. Après
   préparation et passage dans une autre app, faites quitter le Chat au
   technicien, coupez le réseau lors d’un autre essai et essayez une interruption
   système. Vérifiez que le micro cesse et que le retour à MeshCentral ne relance
   pas l’appel. Vérifiez aussi le verrouillage et l’expiration à dix minutes.
4. Exécutez la recette sur **iPhone et iPad**. Dans Chrome, suivez les paquets RTP
   et l’audibilité dans les deux sens pendant l’arrière-plan. Le test sur un autre
   réseau avec TURN est distinct. Fermez l’ancien Chat aux deux extrémités avant
   chaque essai. Partagez seulement l’état de réussite ou d’échec.

En attendant un Build validé, sur un iPad qui gère les fenêtres côte à côte,
gardez MeshCentral visible à côté de l’app à dépanner. Sinon, utilisez un appel
Téléphone ou FaceTime séparé pendant le partage consenti de l’écran.

## Périmètre et vérification

Rust distingue l’accord ordinaire de l’accord audio en arrière-plan. Le pont C
conserve ses symboles et ajoute les événements 3 et 4. L’app accepte uniquement
un appel déjà appairé, avec les deux liaisons audio et le micro actifs et un
signal de vie récent. Tant qu’iOS exécute le code, la perte d’audio, de relais,
du contrôle authentifié, du statut ReplayKit ou l’expiration ferme l’accord.
Au retour dans l’app, l’état est contrôlé avant de reprendre la supervision au
premier plan. Une coupure du relais n’autorise plus MeshMessenger à ouvrir une
nouvelle connexion tout seul. Le micro ne démarre qu’après un accord local et
l’autorisation WebKit. Aucun maintien par son silencieux, tâche de fond forcée,
réveil distant ni nouvelle dépendance.

Apple documente le mode audio. Le code public WebKit vérifie `UIBackgroundModes`
pour décider de suspendre ou non la capture audio lorsque la page est masquée.
Un essai WebKit documenté a fonctionné sur iOS 17.5.1. Cela justifie un candidat
sur appareil et pas une garantie pour chaque version ni un résultat de recette.
L’indicateur système reste essentiel quand l’app n’est plus visible. Le maintien
réel des deux flux, les interruptions et le délai d’arrêt sont à mesurer.

Sous Windows, la mise en forme, Clippy et les 50 tests Rust passent. Les 11 cas
WSS natifs, le pont C Messenger, les tests de négociation et de l’état des deux
flux JavaScript, ainsi que les licences passent. La structure Xcode et les
empreintes du ZIP sont vérifiées. Avant modification, le ZIP 0.4.6 et les 155
empreintes de sources de sa référence correspondaient. Les fichiers locaux
de cette livraison ont disparu pendant la préparation. Le manifeste 0.4.7
référence l’empreinte observée et le paquet contient les chemins édités pendant
ce travail. La fusion finale avec un exemplaire de la livraison à destination
reste à effectuer. Aucun build Xcode, essai simulateur, appel physique
en arrière-plan ni publication n’a été effectué. Version native 0.4.7 et crates
Rust 0.4.3. Les protocoles serveur et la configuration MeshCentral restent les mêmes.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Branche par défaut
distante `master` à `6da4680a61cda2b610ceff28a3e4f0454b0e583c` lors de la vérification.
Les métadonnées Git sont en lecture seule sur ce poste.

Le complément de présélection a été comparé à l’archive 0.4.7 effectivement livrée
et à son instantané. La structure Xcode, les scripts Messenger et la fusion du
complément ont été contrôlés sous Windows. La présélection en interface et le
passage en arrière-plan restent à vérifier sur iPhone et iPad.

[Modes d’arrière-plan Apple](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) · [Comportement WebKit](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/mediastream/cocoa/RealtimeMediaSourceCenterCocoa.mm) · [Essai iOS 17.5.1 documenté](https://bugs.webkit.org/show_bug.cgi?id=233419) · [Fenêtres côte à côte sur iPad](https://support.apple.com/en-us/125309)
