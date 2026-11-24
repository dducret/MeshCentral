<!-- SPDX-License-Identifier: Apache-2.0 -->
# Partage ReplayKit visible dans MeshCentral en 0.5.2

Le 24 novembre 2026, le chat se connectait depuis l’iPad, mais le technicien ne
voyait pas la diffusion dans MeshCentral. Le test a reproduit une cause possible
avec le gestionnaire du serveur. Une ancienne réponse vide indiquant l’absence
de cœur JavaScript pouvait être traitée tardivement et effacer la capacité
Desktop annoncée par l’extension. Le client natif utilise déjà une inscription
sans cœur JavaScript. Il poursuit donc la connexion après la demande
d’effacement et annonce sa capacité Desktop sans envoyer cette réponse vide.
L’iPad affiche **Diffusion prête** après l’envoi de l’annonce. La cause du
symptôme sur l’iPad reste à confirmer avec ce build.

L’app vérifie aussi que l’extension demandée par le sélecteur est intégrée
et que ses réglages compilés correspondent à ceux de l’app. L’extension
vérifie son accès effectif à l’App Group avant de se connecter et remonte une
erreur de démarrage à l’iPad. La confirmation de capture reste celle de
ReplayKit. [Sélecteur de diffusion Apple](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)

## Installer sur la 0.5.1 SDK 26

1. Fusionnez le contenu de `MeshCentral-iOS-0.5.2-diffusion-replaykit-update.zip`
   avec le projet qui a reçu `MeshCentral-iOS-0.5.1-sdk26-rollback.zip`. Le dossier
   cible contient `Cargo.toml` et `apple/`. Aucun fichier à supprimer ou renommer.
2. Dans **Xcode 26**, passez **Version** à **0.5.2** pour **MeshCentralIOS** et
   **MeshCentralBroadcast** et choisissez le même nouveau **Build** pour les deux.
   Gardez vos réglages de signature, Bundle IDs, groupes et mode Audio. Le ZIP
   contient les sources à fusionner et les manifestes. Le projet et les plist
   configurés se conservent.
3. Faites **Clean Build Folder** et installez l’app et l’extension Release du
   même build. Utilisez Rust **0.4.5** comme en 0.5.1. Le panneau web 0.5.0 peut
   être utilisé avec ce correctif.

## Vérifier sur l’iPad

1. Touchez **Préparer le partage d’écran**. Ouvrez le bouton système qui
   s’affiche, puis confirmez **Lancer la diffusion** avec **MeshCentral Screen**.
2. Attendez **Diffusion prête** sur l’iPad. Dans la fiche de ce même iPad côté
   technicien, ouvrez **Desktop → Connecter** ou **Plugins → Assistance iOS →
   Demander une session**. Actualisez la fiche si elle était ouverte avant la
   diffusion. Vérifiez que l’image apparaît après l’accord prévu par le
   parcours choisi, puis testez le masque et l’arrêt.
3. Si l’app reste sur **Partage préparé**, vérifiez que le sélecteur affiche
   **MeshCentral Screen** et que **Lancer la diffusion** a été confirmé. Si
   l’app ou le système affiche une erreur, relevez son libellé. Pour un échec
   d’extension, d’App Group ou de trousseau, vérifiez l’archive installée sur
   le Mac avec `python3 tools/check_sharing_configuration.py <archive.xcarchive>`.
   [Vérifier les deux cibles signées](ipad-sharing-preflight.md)

## Vérifications

Le test sous Windows reproduit l’effacement tardif avec le véritable
`meshagent.js` et une base de test en mémoire, puis vérifie l’événement
`changenode` portant la capacité Desktop. Les contrôles du panneau, des
licences, du projet Xcode et les neuf tests de configuration ReplayKit passent.
Rust reste à 0.4.5. Rustfmt, Clippy, les 52 tests Rust et les 11 scénarios WSS
passent. La compilation Xcode 26 Release, la signature et le test physique
ReplayKit sur l’iPad restent à faire.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Branche distante
`master` à `7d52d950b6d066e7212d7831b87b5da9359651a5` lors de la vérification.
La lecture seule de `.git` a bloqué le fetch et la création de branche.
