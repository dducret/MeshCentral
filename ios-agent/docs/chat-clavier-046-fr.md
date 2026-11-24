<!-- SPDX-License-Identifier: Apache-2.0 -->
# Rédaction lisible et commandes visibles avec le clavier — 0.4.6

Le champ **Votre message** emploie le style Titre 2 d’iOS pour le texte de
saisie et son indication. Il suit Dynamic Type, possède un contour visible
et mesure au moins 52 points de haut. **Envoyer** reste à côté du champ ou
juste en dessous aux grandes tailles de texte. **Terminer** reste en haut
du chat. En paysage, si la hauteur disponible est très réduite, les deux
boutons se placent avec le champ, au-dessus du clavier.

La disposition utilise l’espace que SwiftUI réserve au-dessus du clavier.
Le champ conserve son identité quand l’écran change de taille. En faible
hauteur, il défile au-delà d’une ligne au lieu de repousser **Envoyer**.
L’historique cède la place aux commandes, sans être recréé. Le micro reste
accessible dans la barre supérieure et l’état d’un partage actif reste
affiché. L’icône clavier permet de masquer le clavier sans quitter le chat.

Le champ reste disposé à recevoir du texte pendant un envoi. Un échec conserve
le brouillon. Un succès efface uniquement le brouillon soumis s’il est encore
identique. L’envoi ne réclame pas le focus si l’utilisateur a masqué le clavier
pendant l’attente. Le bouton **Terminer** masque le clavier et réutilise l’arrêt
de session existant.

## Appliquer et tester

1. Appliquez ce complément à la 0.4.6 issue de
   `MeshCentral-iOS-0.4.6-texte-chat-update.zip`. Fusionnez
   `MeshCentral-iOS-0.4.6-clavier-chat-update.zip` dans la racine du projet
   qui contient `Cargo.toml` et `apple/`. La liste et les empreintes sont dans
   `release-0.4.6-clavier.json` et `SHA256SUMS-0.4.6-clavier.json`.
   Aucun fichier à supprimer ou renommer.
2. Gardez la Version 0.4.6 et utilisez un nouveau Build commun à l’app et
   à l’extension. Conservez le projet Xcode configuré et le framework Rust 0.4.2.
3. Sur iPhone, en portrait puis en paysage, ouvrez le clavier dans un chat.
   Essayez des messages courts et longs, à taille normale puis à taille
   d’accessibilité maximale. Vérifiez que **Envoyer** et **Terminer** sont
   lisibles et accessibles sans masquer le clavier.
4. Avec un message en cours, masquez le clavier par la barre supérieure.
   Rouvrez-le et envoyez. Vérifiez la saisie après un envoi, la conservation
   du brouillon après un refus d’envoi et l’arrêt avec le clavier ouvert.
   Répétez sur iPad en vue partagée, puis avec VoiceOver et un partage actif.

Les contrôles Windows couvrent les scripts Messenger existants, les licences
et la structure Xcode. Le ZIP et sa fusion avec la base 0.4.6 ont été vérifiés.
Les essais Xcode et le rendu réel iPhone/iPad restent à effectuer.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. La branche distante
par défaut `master` pointait sur `6da4680a61cda2b610ceff28a3e4f0454b0e583c`.
Les métadonnées Git sont en lecture seule sur ce poste. Aucune modification
au protocole, aux dépendances, à l’enrôlement ou à la signature.

[Zone du clavier SwiftUI](https://developer.apple.com/documentation/swiftui/safearearegions/keyboard) · [Limite de lignes du champ vertical](https://developer.apple.com/documentation/swiftui/view/linelimit%28_%3A%29?changes=_3)
