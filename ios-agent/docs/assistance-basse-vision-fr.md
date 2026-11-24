<!-- SPDX-License-Identifier: Apache-2.0 -->
# Assistance iPad lisible avec une basse vision

Ce complément 0.4.5 affiche **Accepter avec le micro**, **Accepter sans
micro**, **Refuser** et **Terminer** sur toute la largeur disponible, avec
une hauteur d’au moins 96 points. Les libellés utilisent le grand titre gras du système et
peuvent passer sur plusieurs lignes. Le bleu et le rouge foncés affichent un
texte blanc à fort contraste. Le bouton secondaire associe un libellé foncé
ou clair au fond système et à un contour visible.

L’invitation occupe l’écran avec trois choix verticaux et un défilement
possible. VoiceOver peut placer le focus sur son titre et les commandes
derrière l’invitation ne sont pas accessibles pendant l’invitation. Le bouton
d’arrêt reste présent si l’écran est partagé. Dans le chat, **Terminer** est
épinglé au-dessus du contenu, à portée même lorsque l’historique défile. Les
commandes de connexion, de partage, du micro et de confirmation d’arrêt ont
aussi une surface plus grande. Le champ et le bouton **Envoyer** s’empilent
pour les tailles de texte d’accessibilité.

## Appliquer et essayer

Depuis le projet qui a reçu `MeshCentral-iOS-0.4.5-assistance-gestes-update.zip`,
fusionnez les fichiers de `MeshCentral-iOS-0.4.5-assistance-visible-update.zip`
à la racine contenant `Cargo.toml` et `apple/`. L’archive fournit la liste et
les empreintes. Conservez le projet Xcode configuré et la version 0.4.5.
Utilisez un nouveau numéro de Build commun aux deux cibles. Aucun fichier
à supprimer ou renommer.

1. Avec **Réglages → Accessibilité → Affichage et taille du texte → Texte plus
   grand**, testez la taille normale puis la taille maximale. Vérifiez en
   portrait, paysage et en vue partagée que les trois choix s’affichent en
   entier et restent accessibles par défilement.
2. Activez VoiceOver et vérifiez le titre, le nom du technicien et les trois
   choix dans cet ordre. Vérifiez les actions avec et sans micro. Le refus
   doit ramener à l’écran précédent.
3. Ouvrez le clavier dans le Chat. Vérifiez que le bouton **Terminer** reste
   accessible en haut, que le message peut être envoyé, puis que l’arrêt
   éteint le point orange et ramène à l’accueil. Testez également en mode sombre.
4. Avec un partage actif, vérifiez que **Terminer** reste accessible depuis
   l’invitation et que l’arrêt de la diffusion est confirmé par iPadOS.

Les tests Messenger et de licence passent sous Windows. Les scripts WebRTC
et de consentement injectés correspondent exactement au paquet précédent.
Les couleurs actives avec texte blanc ont un contraste calculé supérieur à
8:1. Les références Xcode existantes et le ZIP incrémental ont été vérifiés.
Xcode, VoiceOver et la mise en page réelle sur iPad restent à tester.

Référence locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. La branche par
défaut distante était `master` à `1eab6b80c90f9e9911f178aa518bf2192e47602c`.
Les métadonnées Git sont en lecture seule sur ce poste. Les modifications
s’appliquent aux vues SwiftUI. La signature, ReplayKit et Rust restent dans
leurs composants existants.

[Recommandations Apple pour les grands caractères](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria/)
