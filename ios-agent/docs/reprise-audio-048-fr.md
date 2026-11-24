<!-- SPDX-License-Identifier: Apache-2.0 -->
# Reprendre le son dans MeshCentral 0.4.8

Quand une autre app interrompt un appel déjà établi, revenez dans MeshCentral
et touchez **Reprendre le son**. Le bouton est prévu pour iPhone et iPad. Il
s’affiche au-dessus du chat, près de **Terminer**, et suit la taille du texte
du système. Vous pouvez toujours écrire dans la conversation pendant la pause.
Le maintien audio en arrière-plan utilise le mode audio de l’app et requiert
un appareil physique sous iOS ou iPadOS 17.5.1 ou ultérieur.

La reprise exige le même relais Messenger, la même session d’assistance
connectée et l’accord initial toujours valide. Si le technicien ferme le Chat,
si la connexion est perdue ou si l’accord expire, il faut une nouvelle invitation.
L’accord expire dix minutes après la réception de l’invitation. Le système
peut suspendre ou fermer la conversation pendant l’utilisation d’une autre app.

## Installer sur votre projet 0.4.7

1. Partez de la 0.4.7 avec le complément
   « MeshCentral-iOS-0.4.7-audio-par-defaut-update.zip » déjà appliqué.
2. Fusionnez le contenu du dossier du ZIP « MeshCentral-iOS-0.4.8-reprise-audio-update.zip »
   avec la racine du projet qui contient « Cargo.toml » et « apple/ ». Les
   fichiers remplacés et leurs empreintes figurent dans les deux manifestes du ZIP.
   Aucun fichier à supprimer ou renommer.
3. Dans votre projet Xcode configuré, réglez **Version** sur **0.4.8** pour
   l’app MeshCentralIOS et son extension de diffusion. Choisissez le même
   nouveau numéro de **Build** pour les deux. Conservez la signature et les
   identifiants, les groupes d’apps et de trousseau et le mode audio déjà activé
   dans l’app. Le projet Xcode reste en place.
4. Faites **Clean Build Folder** et compilez en **Release**. La phase Rust
   standard reconstruit le cœur **0.4.4**. Si un « MeshCore.xcframework » a été
   intégré manuellement, reconstruisez-le avec « sh apple/build-xcframework.sh ».
   Réinstallez les deux cibles du même build sur l’iPhone ou l’iPad.

## Vérifier sur appareil physique

1. Lancez **Chat** dans le navigateur du technicien. Sur le mobile, vérifiez
   que **Garder le son dans les autres apps** est coché et touchez **Accepter
   avec le micro**. Vérifiez le son dans les deux sens et envoyez un message.
2. Ouvrez d’abord Notes et vérifiez que le son continue. Revenez dans
   MeshCentral, puis ouvrez **Unlock!** avec le son et lancez une aventure. Si
   le son est interrompu, revenez et vérifiez que le micro reste coupé et que
   **Reprendre le son** et **Terminer** sont visibles. Envoyez un message
   pendant la pause et confirmez que la fenêtre Chat du technicien est la même.
3. Touchez **Reprendre le son** une fois. Vérifiez que chacun entend l’autre
   dans la même conversation, que le texte fonctionne et que l’historique est
   toujours visible. Avec Chrome, vérifiez la progression des compteurs RTP
   entrants et sortants. Vérifiez la présentation avec le grand texte système
   et le clavier sur iPhone, puis recommencez sur iPad avec ReplayKit actif.
4. Dans des essais séparés, fermez le Chat côté technicien, coupez le réseau et
   laissez expirer l’accord pendant l’interruption. Vérifiez que chaque
   scénario exige une nouvelle invitation et que le micro ne se réactive pas.
   Vérifiez aussi **Terminer** pendant la pause et pendant la reprise.
   Fermez l’ancien Chat aux deux extrémités entre les essais.

## Comportement technique

Le passage en arrière-plan ouvre la possibilité de reprise si l’utilisateur a
accepté le maintien audio et si les deux flux étaient actifs récemment.
Si la liaison multimédia est interrompue, l’app coupe la transmission du micro
et suspend la lecture de la WebView. Rust autorise le maintien de ce chat
avec l’événement C 5, dans la durée du même accord.

Au retour, le bouton vérifie la connexion de contrôle et l’accord Rust.
La WebView vérifie le socket Messenger d’origine avant de réactiver la lecture
ou demander le micro. Si la piste sortante est inutilisable avec le
MeshMessenger 1.3.1, les fonctions de la page renégocient cette piste via le
même relais. Les sessions WebRTC de texte et d’audio entrant restent en place.
La fermeture du chat ou le rechargement de la page révoque l’accord.
L’app utilise les API publiques de WebKit et ne demande aucune exécution
supplémentaire en arrière-plan.

[Lecture et capture dans WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
· [Exécution en arrière-plan dans UIKit](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)

## Vérifications locales

Sous Windows, la mise en forme, Clippy et les 51 tests Rust passent.
Le test du pont C vérifie le maintien d’un appel interrompu et la révocation à
l’expiration ou à la déconnexion. Les 11 cas WSS natifs et les vérifications
de licences passent. Les tests JavaScript passent avec la page locale et la
page officielle de MeshCentral 1.3.1. Ils vérifient notamment le même relais,
le maintien du canal de texte et la gestion d’une capture rendue après l’arrêt
de la reprise. La structure du projet Xcode et les neuf contrôles de diffusion
passent également.

Le ZIP a été comparé à l’archive réellement livrée et aux 156 empreintes de la
0.4.7 avec présélection. Le build Xcode Release, la signature, XCTest et la
recette de la reprise avec Unlock! sur iPhone et iPad restent à exécuter.

Révision de travail « 67aff175f6d1093b1a81f8e9230607854d3fbaa6 ». La branche
distante « master » pointait sur « 6da4680a61cda2b610ceff28a3e4f0454b0e583c ».
Les métadonnées Git en lecture seule ont bloqué le fetch et la création de branche.
