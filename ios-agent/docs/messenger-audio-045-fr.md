<!-- SPDX-License-Identifier: Apache-2.0 -->
# Microphone MeshMessenger sur iPad — 0.4.5

La 0.4.4 a permis un échange de texte dans les deux sens. Sur l’iPad, le bouton
micro était grisé avec « Audio en attente de WebRTC ». Dans la fenêtre Chat du
technicien, l’icône micro était absente. L’utilisateur a aussi signalé une page
blanche et l’absence de réglage Microphone pour l’app. Une app sans demande d’accès
peut être absente de la liste Microphone. L’écran blanc n’a pas été reproduit.

## Appliquer le correctif

1. Partez du projet 0.4.4 ayant reçu le [complément de récupération Swift](ipad-chat-044-recovery-fr.md).
   Décompressez `MeshCentral-iOS-0.4.5-messenger-audio-update.zip` et fusionnez les
   fichiers fournis dans la racine contenant `Cargo.toml` et `apple/`.
   Référez-vous à `release-0.4.5.json` pour la liste et à `SHA256SUMS-0.4.5.json`
   pour vérifier les empreintes. La livraison ne requiert ni suppression ni renommage.
2. Dans Xcode, fixez **Marketing Version à 0.4.5** et incrémentez le même **Build**
   pour l’app et l’extension. Gardez les valeurs Team, Bundle IDs, App Groups,
   Keychain et la signature du projet existant. Réutilisez `MeshCore.xcframework`
   0.4.2. Vérifiez que l’`Info.plist` de la **cible app** contient une valeur non
   vide pour `NSMicrophoneUsageDescription`. Gardez cette valeur si elle existe.
3. Faites **Clean Build Folder**, compilez, exécutez **Product → Test** et installez
   le nouveau Build sur l’iPad. Vérifiez que MeshCentral affiche 0.4.5.

## Vérifier sur l’iPad

1. Ouvrez **Options → Se connecter pour le chat uniquement**, puis laissez l’app
   au premier plan. Depuis le site, ouvrez **Chat** et acceptez sur l’iPad.
   Échangez un message dans chaque sens.
2. Même si WebRTC se connecte encore, touchez **Activer le microphone**. Lors de
   la première demande, acceptez l’accès au micro dans les dialogues présentés.
   S’il avait été refusé auparavant, vérifiez **Réglages → Confidentialité et
   sécurité → Microphone**, puis revenez et acceptez une nouvelle invitation.
3. Vérifiez séparément **Microphone actif sur cet appareil** et **Liaison audio
   sortante établie**. Dites quelques mots et demandez au technicien de confirmer
   qu’il vous entend. Quand l’icône apparaît dans sa fenêtre, il peut activer son
   micro pour tester l’autre sens. Vérifiez Couper, Réactiver et Fermer, puis
   vérifiez qu’un passage en arrière-plan coupe la conversation.
4. Si la liaison reste indisponible ou que l’icône est toujours absente côté
   technicien, refaites le test avec les deux appareils sur le même réseau.
   Si le problème ne se produit que sur des réseaux différents, vérifiez que
   les deux navigateurs peuvent joindre le serveur TURN déclaré dans
   `settings.webrtcConfig.iceServers`. STUN seul ne peut pas relayer l’audio.
   Faites ce diagnostic avant de modifier un serveur utilisé en production.

Si l’écran reste blanc, notez s’il s’agit de Réglages iPadOS ou de la fenêtre de
chat, si **Votre message** est visible, et le libellé affiché sous le micro.
Ces informations suffisent pour distinguer un problème d’affichage d’un échec
audio. Le texte reste accessible lorsque seule la liaison audio échoue.
