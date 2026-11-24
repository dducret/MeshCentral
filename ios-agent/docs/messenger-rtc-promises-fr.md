<!-- SPDX-License-Identifier: Apache-2.0 -->
# Négociation audio MeshMessenger 1.3.1 sur iOS

Ce complément s’applique aux sources de `MeshCentral-iOS-0.4.5-messenger-audio-update.zip`.
La version reste **0.4.5**. L’adaptateur est chargé en Debug et en Release.
Le serveur reste sur son installation MeshCentral 1.3.1 standard.

## Appliquer et compiler

1. Fusionnez les fichiers du ZIP dans le projet existant, à la racine contenant
   `apple/` et `Cargo.toml`. L’archive fournit les fichiers modifiés et leurs
   empreintes. Aucun fichier à supprimer ou à renommer.
2. Dans Xcode, vérifiez que la cible app référence le fichier
   `apple/App/Sources/AssistanceView.swift` mis à jour. Si votre copie contient
   le prototype expérimental, gardez-en une copie pour comparaison et utilisez
   le fichier livré. Le prototype doit être retiré de la cible avant l’essai.
3. Conservez le projet configuré, le framework Rust 0.4.2, la signature et
   l’enrôlement. Choisissez un nouveau numéro de Build commun à l’app et à
   l’extension pour identifier l’installation. Vérifiez que le schéma de lancement
   utilise **Release**, faites **Clean Build Folder**, puis lancez l’app sur le
   simulateur iPhone. Relevez le Build réellement exécuté.

## Vérifier avec les commandes normales

1. Fermez l’ancien chat sur **les deux** participants avant chaque essai.
   Ouvrez `chrome://webrtc-internals` dans Chrome avant de lancer un nouveau
   **Chat** sur MeshCentral. Acceptez l’invitation dans l’app et envoyez un
   message dans chaque sens pour établir la liaison texte.
2. Vérifiez dans Chrome qu’une offre et une réponse SDP ont été appliquées au
   pair du canal de données et que celui-ci atteint `open`. Sur iOS, touchez
   **Activer le microphone** et accordez l’accès si le système le demande.
   Cliquez aussi sur le bouton microphone normal de Chrome. Gardez les deux
   micros actifs dans **la même conversation** pour les étapes suivantes.
3. Vérifiez les échanges offre/réponse des deux pairs audio dans Chrome. Après
   l’établissement de chaque liaison ICE, comparez deux mesures espacées de
   quelques secondes. L’`inbound-rtp` audio de Chrome doit augmenter côté
   `packetsReceived` et l’`outbound-rtp` audio côté `packetsSent`. Vérifiez aussi
   les rapports `remote-inbound-rtp` quand ils sont disponibles. Notez l’audibilité
   dans chaque sens séparément en faisant parler chaque participant à tour de rôle.
4. Pour chaque pair audio, suivez `transport.selectedCandidatePairId` vers
   la paire sélectionnée, puis `localCandidateId` et `remoteCandidateId` vers
   les deux `candidateType`. La paire doit être celle effectivement utilisée
   pendant la progression RTP. Un type `relay` sur cette paire indique un relais
   TURN. Si les paires sont directes, consignez-le et répétez sur deux réseaux
   distincts. Deux réseaux distincts ne suffisent pas à eux seuls à prouver TURN.
5. Fermez le chat aux deux extrémités. Répétez l’essai sur l’iPad physique pour
   vérifier la demande d’accès, l’audibilité, la coupure et la réactivation du
   micro, puis sa fermeture avec la conversation. Notez séparément le résultat
   simulateur, le résultat iPad et la présence éventuelle de TURN.

En Debug, les lignes `MeshMessenger RTC` donnent le nom de l’opération et son
résultat prédéfini. Release n’émet pas ces lignes. Pour partager un résultat,
indiquez uniquement le Build, les phases observées, les types de candidats
sélectionnés, la progression RTP et l’audibilité. Gardez les exports bruts de
Chrome et les URL de conversation sur le poste de test.

## Si l’iPad entend le technicien mais reste inaudible

Sur l’iPad, vérifiez **Microphone actif sur cet appareil** et le point orange.
**Liaison audio sortante établie** indique que la connexion ICE est ouverte.
Dans la fenêtre Chat de Chrome, cliquez sur **Click here to view** si cette
action est proposée, et vérifiez que le son du site est autorisé.

Dans `chrome://webrtc-internals`, plusieurs connexions peuvent porter le même
nom MeshMessenger. L’entrée qui contient `data-channel` avec `DataChannel`
correspond à la connexion de données. Choisissez celle qui contient
`inbound-rtp` avec `kind=audio`. Comparez `packetsReceived` et
`totalAudioEnergy` avant et après avoir parlé quelques secondes depuis l’iPad.
Dans **Stats Tables**, développez la ligne de ce rapport pour voir les chiffres.
Si l’énergie manque dans la table, développez les graphiques audio et cherchez
`[audioLevel]`. Transmettez seulement les deux valeurs avant/après ou dites
qu’une mesure est absente. Les titres des rapports indiquent le flux négocié,
mais ne montrent pas la progression.

- Si les paquets et l’énergie augmentent lorsque vous parlez, cliquez sur le
  cadre **Remote** dans la fenêtre Chat, même s’il est noir. Ce clic déclenche
  la lecture du flux. Vérifiez ensuite que le site est autorisé à jouer du son
  et que le mélangeur du système envoie Chrome vers le bon casque ou haut-parleur.
- Si les paquets augmentent mais que l’énergie reste nulle, faites un essai
  sans casque Bluetooth ni entrée USB, et vérifiez la voix dans un bref
  enregistrement local avec Appareil photo avant de rouvrir un chat.
- Si les paquets restent à zéro ou que le flux n’apparaît pas, examinez le
  pair audio sortant de l’iPad. Vérifiez l’offre/réponse, `packetsSent` et la
  paire ICE sélectionnée. Les deux sens utilisent des pairs audio distincts.

Une statistique absente ne doit pas être interprétée comme une valeur nulle.
