<!-- SPDX-License-Identifier: Apache-2.0 -->
# Séance d’assistance et masquage de l’écran en 0.5.0

La séance s’ouvre quand le partage démarre ou quand vous acceptez un Chat. Elle
affiche le technicien, l’état du chat, du microphone et de l’écran. Dans une
séance avec Chat, **Terminer** reste à portée du clavier. **Reprendre le son**
réutilise la conversation et l’accord initial, tant qu’ils sont encore valides.

Pour utiliser ensemble l’écran et l’appel sur un appareil physique, préparez et
lancez d’abord la diffusion iPadOS, puis demandez au technicien d’ouvrir la
visualisation et d’envoyer l’invitation **Chat**. Acceptez l’invitation avec le
micro et gardez l’option d’audio en arrière-plan si vous devez changer d’app.
Cette option requiert un appareil physique sous iOS ou iPadOS 17.5.1 ou plus
récent et le mode Audio déjà configuré en 0.4.8.

## Masquer et réafficher son écran

1. Touchez **Masquer mon écran** dans la séance. En vue compacte avec clavier,
   utilisez le bouton avec l’icône d’œil dans la barre du haut. Attendez
   **Écran masqué** avant d’ouvrir un écran privé.
2. Le panneau du technicien efface l’image en direct, affiche **Écran masqué
   sur l’appareil** et suspend les nouvelles demandes de capture. Le Desktop
   MeshCentral standard utilise son message de console et une image noire.
   La voix et le chat gardent leurs connexions actives pendant le masquage.
3. Revenez dans MeshCentral et touchez **Partager de nouveau mon écran** pour
   envoyer des images fraîches. La diffusion iPadOS et son indicateur restent
   actifs pendant le masquage. **Terminer** révoque l’accord et arrête les échanges.
   Après un arrêt, une déconnexion ou l’expiration, recommencez avec un nouvel accord.

Les images déjà vues, enregistrées ou conservées par le destinataire peuvent
rester disponibles. Le masquage bloque les nouveaux échantillons vidéo et annule
une capture en attente. Le maintien du son lors d’un changement d’app reste
soumis au comportement d’iOS et à l’accord audio. Si une autre app interrompt le
son mais que le Chat reste connecté, **Reprendre le son** est disponible au retour.

## Installer le ZIP depuis la livraison 0.4.8

1. Partez du projet qui a reçu **MeshCentral-iOS-0.4.8-reprise-audio-update.zip**.
   Fusionnez le contenu de **MeshCentral-iOS-0.5.0-seance-update.zip** à la racine
   qui contient `Cargo.toml`, `apple/` et `operator/`. Les deux manifestes du
   ZIP donnent les chemins et empreintes. Aucun fichier à supprimer ou renommer.
2. Dans votre projet Xcode configuré, réglez **Version** sur **0.5.0** pour l’app
   et l’extension de diffusion. Choisissez le même nouveau numéro de **Build**
   pour les deux. Conservez le projet, la signature, les Bundle IDs, les groupes
   d’apps et de trousseau, les profils et le mode Audio de l’app.
3. Faites **Clean Build Folder** et compilez et installez les deux cibles en
   **Release**. La phase Rust standard reconstruit le cœur **0.4.5**. Si vous avez
   intégré le framework manuellement, reconstruisez `MeshCore.xcframework` avec
   `sh apple/build-xcframework.sh` depuis la racine et utilisez ce framework dans
   les deux cibles.
4. Dans le dossier web personnalisé de votre serveur, remplacez les fichiers
   `ios-assist.html` et `ios-assist.js` par ceux d’`operator/`. Rechargez le
   panneau, puis ouvrez une nouvelle séance. Le plugin 0.1.0 utilise les mêmes
   fichiers web. Suivez [la notice du panneau](../operator/README.md) pour trouver
   le dossier de votre domaine.

## Recette Release sur iPhone et iPad physiques

1. Relevez le Build installé. Testez une séance avec chat seul, une avec écran
   seul, puis une avec les deux. Vérifiez le nom du technicien, les états
   écran/chat/micro, le bouton **Terminer** avec clavier ouvert et l’historique
   après plusieurs masquages. Répétez en portrait et paysage avec VoiceOver et
   les grands caractères.
2. Pendant une séance avec son bidirectionnel et partage, masquez et attendez
   la confirmation. Ouvrez ensuite Notes avec un texte d’essai. Le technicien
   doit voir uniquement l’état masqué dans le panneau. Répétez avec la
   visualisation **Desktop** standard dans une autre séance. Vérifiez la voix
   dans les deux sens, envoyez des messages sous masque, puis réaffichez l’écran
   par une action locale. Vérifiez que la première image réaffichée est récente.
3. Mettez une capture en attente, puis masquez. Vérifiez qu’elle est annulée et
   qu’aucune capture nouvelle ne peut être demandée pendant le masquage.
   Envoyez un message et demandez un document de test avec son accord séparé.
4. Masquez puis déclenchez une interruption audio avec une app qui utilise le
   son. Revenez et essayez **Reprendre le son** si le Chat est resté ouvert.
   Testez séparément **Terminer**, l’arrêt système, une coupure réseau et
   l’expiration sous masque. Chaque nouvelle séance doit exiger un nouvel accord.
5. Répétez l’essai audio avec le navigateur et l’appareil sur deux réseaux.
   Relevez les paires effectivement sélectionnées et confirmez le type
   `relay` pour l’essai TURN. [Recette WebRTC et TURN](messenger-rtc-promises-fr.md)

## Comportement technique et vérifications

Rust lie le masquage à l’accord de visualisation actif. Le pont traite
séparément l’autorisation de vidéo et celle des échanges. L’app écrit une
commande bornée dans le trousseau partagé. L’extension vérifie son propriétaire,
sa fraîcheur et sa révocation, puis arrête d’alimenter l’encodeur. Le relais
rejette les anciens producteurs, purge la dernière image accessible à la
capture et attend la fin de l’envoi WebSocket de l’image noire avant de
confirmer le masquage à l’app. Chaque reprise crée un nouveau producteur.
Le panneau efface son canevas et invalide tout décodage entamé avant le masquage.
L’action `screenVisibility` est envoyée de l’agent vers le panneau dans le
protocole `iosAssist` v1. Le bouton utilise la diffusion ReplayKit et le chat
WebKit existants. [Apple ReplayKit](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler) · [Apple WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)

Sous Windows, rustfmt, Clippy et les 52 tests Rust passent. Les 11 cas natifs
WSS, les contrôles du pont C, les tests MeshCentral et du panneau, les
vérifications de licence, la structure Xcode et les neuf tests de configuration
de diffusion passent. Le test du panneau couvre un décodage tardif et un chat
qui continue sous masque. La compilation et la signature Xcode, XCTest, le rendu
dans un navigateur connecté au serveur et la recette physique restent à effectuer.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Branche distante
`master` à `6da4680a61cda2b610ceff28a3e4f0454b0e583c` lors de la vérification.
La lecture seule de `.git` a bloqué le fetch et la création de branche.
Le ZIP est comparé à l’archive effective 0.4.8 et à ses 157 empreintes de
référence.
