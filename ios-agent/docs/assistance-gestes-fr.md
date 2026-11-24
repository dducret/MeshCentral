<!-- SPDX-License-Identifier: Apache-2.0 -->
# Moins de gestes pour le chat et la fin de l’assistance

Le 23 novembre 2026, l’utilisateur a confirmé le son dans les deux sens sur
iPad. Le flux iPad vers Chrome utilisait une paire ICE directe sur le réseau
local. L’essai audio via TURN reste à faire. Ce complément 0.4.5 simplifie le
parcours iOS à partir du paquet `MeshCentral-iOS-0.4.5-messenger-rtc-promises-update.zip`.

Depuis l’accueil, touchez **Se connecter pour le chat**. Quand le technicien
envoie son invitation, **Accepter avec le micro** ouvre le chat et demande le
micro dès que la connexion est prête. **Accepter sans micro** ouvre le texte
seul. Les deux actions affichent le nom du technicien. Une demande système peut
encore s’afficher. L’app n’utilise le micro que pour l’invitation acceptée.

**Terminer** ferme le chat, coupe le micro, déconnecte la session et ramène à
l’accueil. Pendant un partage, le même bouton demande l’arrêt de la diffusion.
Le statut reste visible jusqu’à l’accusé d’arrêt. Pour garder l’écran partagé,
le menu du chat propose **Fermer seulement le chat**. Le geste Accueil d’iPadOS
permet ensuite de quitter l’app. Le bouton **Préparer le partage d’écran** garde
le sélecteur ReplayKit et sa confirmation système.

## Appliquer le complément

Fusionnez les fichiers de `MeshCentral-iOS-0.4.5-assistance-gestes-update.zip`
à la racine du projet existant, celle qui contient `Cargo.toml` et `apple/`.
Utilisez la liste de `release-0.4.5-assistance-gestes.json` et les empreintes de
`SHA256SUMS-0.4.5-assistance-gestes.json`. Aucun fichier à supprimer ou renommer.
Gardez la Version 0.4.5 et choisissez un nouveau Build commun à l’app et à
l’extension. Conservez le projet Xcode configuré, la signature et
`MeshCore.xcframework` 0.4.2.

## Essai sur iPad

1. Lancez un Build Release sur iPad. Connectez-vous depuis l’accueil et acceptez
   avec le micro. Accordez l’accès si iPadOS le demande. Vérifiez le texte et
   parlez dans les deux sens dans la même conversation.
2. Touchez **Terminer** avec le clavier ouvert puis fermé. Vérifiez le retour
   à l’accueil, l’extinction du point orange et la déconnexion dans MeshCentral.
   Refaites un essai depuis Options pour vérifier le retour direct à l’accueil.
3. Essayez **Accepter sans micro** et **Refuser**. Le micro doit rester éteint.
   Après un refus système, vérifiez qu’un nouveau toucher local est nécessaire
   pour retenter l’activation. Si la connexion tarde plus de 30 secondes, le
   bouton **Activer le microphone** reste le moyen d’activer le micro.
4. Terminez pendant que le technicien ouvre le chat, puis passez en arrière-plan
   pendant un autre essai. Vérifiez qu’une demande différée ne rallume pas le
   micro et qu’une nouvelle conversation exige une nouvelle invitation.
5. Lancez un partage d’écran et un chat. Vérifiez le comportement de **Fermer
   seulement le chat**, puis relancez le chat et vérifiez que **Terminer** arrête
   les deux. En cas d’arrêt non confirmé, suivez le contrôle iPadOS affiché.

Quand ce parcours est validé sur iPad, répétez l’essai audio sur deux réseaux
différents et relevez la paire ICE réellement sélectionnée. La procédure WebRTC
précédente détaille les compteurs et l’identification de TURN.
