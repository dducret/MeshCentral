<!-- SPDX-License-Identifier: Apache-2.0 -->
# Ajouter la conversation MeshMessenger sur iPad — 0.4.1

Ce complément est un **candidat source à compiler et valider sur Mac/iPad**.
Il ajoute le parcours **Chat du site → invitation dans l’app → microphone dans
MeshMessenger**. L’audio fonctionne dans l’app au premier plan ; il est fermé si
vous ouvrez Réglages ou une autre application. Il ne s’agit pas d’un appel VoIP
en arrière-plan. Le partage d’écran ReplayKit conserve son fonctionnement séparé.

## Installer sur la base livrée

1. Appliquez d’abord `MeshCentral-iOS-0.4.0-ipad-assistance-update.zip`
   (SHA-256 `77521a5ae15ed57bb44cda8c5c0c17bfa40b61301760e11b167c7ff927e55560`),
   après ses prérequis 0.3.0. Une livraison antérieure ne prouve pas son installation.
   Arrêtez la diffusion et sauvegardez votre projet configuré avant toute fusion.
2. Décompressez `MeshCentral-iOS-0.4.1-messenger-update.zip`. Depuis son dossier
   `MeshCentral-iOS-0.4.1-messenger-update`, vérifiez les empreintes :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   for name, expected in json.loads(pathlib.Path('SHA256SUMS-0.4.1.json').read_text()).items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, name
   print('Empreintes conformes')
   PY
   ```

3. Fusionnez les fichiers dans le projet existant, celui contenant `Cargo.toml` :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Adaptez le chemin, comparez vos modifications locales et n’utilisez pas
   `--delete`. Aucun fichier à supprimer/renommer. Aucun remplacement complet du
   projet ou du serveur. **Ne lancez pas `generate_xcode.py`.**
4. Dans **votre** `apple/App/Info.plist`, ajoutez seulement la clé
   **Privacy - Microphone Usage Description / `NSMicrophoneUsageDescription`** :
   « Parler avec le technicien dans une conversation MeshMessenger que vous avez
   acceptée. » Conservez un texte local existant s’il décrit déjà cet usage.
   Ne modifiez pas le plist de l’extension. Aucun accès caméra ni mode audio en
   arrière-plan n’est nécessaire. L’app signale cette clé manquante avant ouverture.
5. Dans Xcode, mettez **Marketing Version à 0.4.1** pour l’app et l’extension,
   Debug et Release. Choisissez le même **Build**, supérieur aux versions déjà
   envoyées. Gardez Team, Bundle IDs, App Groups, Keychain, profils et préférences.
   Les fichiers Swift modifiés sont déjà référencés : aucun ajout au projet requis.
6. Faites **Clean Build Folder**, **Product → Test**, puis compilez l’app et
   l’extension pour appareil et archive Release. Vérifiez la clé microphone dans
   l’Info.plist du produit construit et les groupes réellement signés selon
   [le contrôle existant](ipad-sharing-preflight.md).
7. Installez ensemble les deux cibles 0.4.1 selon votre canal habituel. Aucun
   fichier serveur/plugin/panneau opérateur à remplacer pour ce complément.

Les modifications manuelles figurent dans `release-0.4.1.json`. Le ZIP ne contient
ni Info.plist ni `.pbxproj` afin de préserver votre configuration. Les checksums
globaux et la base sont conservés dans le manifeste local de livraison.

## Déclencher depuis le site MeshCentral

**Conversation seule :** sur l’iPad, ouvrez MeshCentral et touchez **Se connecter**.
Gardez l’app ouverte. Sur le site, choisissez cet iPad dans **Mes appareils**, puis
cliquez sur **Chat** dans sa fiche **General** (entre Message et Share selon le thème).

**Pendant un partage d’écran :** préparez et lancez la diffusion comme en 0.4.0.
Le technicien clique sur le même bouton **Chat** de la fiche de l’iPad. Revenez
dans l’app MeshCentral pour voir l’invitation ; aucune ouverture automatique
d’application ni notification push n’est ajoutée.

Sur l’iPad, vérifiez le nom puis touchez **Ouvrir la conversation**. Dans la fenêtre
MeshMessenger, touchez **Activer le microphone** dans les commandes de l’app
(ou l’icône microphone de la page) et autorisez son utilisation. La commande native
permet aussi de demander le micro si son icône web n’est pas encore affichée ;
elle attend toutefois la connexion WebRTC. Le
technicien active aussi son microphone dans sa fenêtre web. Si le navigateur
demande un geste pour lire le son, touchez la zone distante indiquée.

Le bandeau natif indique **microphone actif**, **coupé** ou **inactif**. Utilisez
**Couper/Réactiver le microphone** ou **Fermer la conversation**. Fermer Messenger
seul conserve un éventuel partage d’écran. **Arrêter l’assistance** met fin au
partage et à la conversation. Après une interruption, demandez un nouveau clic
Chat et acceptez la nouvelle invitation. Une invitation expire après deux minutes ;
une conversation dure au plus dix minutes depuis son invitation.

## Si le microphone ou la conversation ne s’ouvre pas

- **Invitation absente :** app connectée ou extension active, retour dans l’app,
  bon appareil sélectionné, droits **Remote Control / Chat & Notify** et nouveau
  clic Chat. Le nom d’agent doit annoncer `0.4.1`. Le serveur vérifié ne lance pas
  ce parcours appareil en mode `LAN-only`.
- **Microphone absent dans Messenger :** les deux fenêtres doivent être présentes,
  le navigateur doit détecter un microphone et établir WebRTC. Le chat textuel
  peut fonctionner alors que le chemin audio est bloqué. Vérifiez les autorisations
  et la configuration STUN/TURN/réseau existante ; ne désactivez pas TLS.
- **Accès refusé :** vérifiez l’autorisation microphone de MeshCentral dans iPadOS.
  Après modification hors de l’app, demandez une nouvelle invitation.
- **Erreur de page/certificat :** l’URL web doit avoir le même hôte/port HTTPS que
  l’enrôlement WSS et le bon domaine. Les déploiements avec port agent distinct ne
  sont pas pris en charge par ce candidat. Une autorité privée doit aussi être
  validée pour les connexions WebKit sur appareil.

## Recette obligatoire avant validation

Notez iPad/modèle, iPadOS, Xcode/SDK, Version/Build, révision MeshCentral,
navigateur technicien et réseau. Utilisez une conversation et des fichiers factices.

| Essai | Résultat attendu |
| --- | --- |
| Chat vers iPad connecté, sans écran partagé | Une invitation avec le nom du technicien ; aucun micro avant acceptation et action microphone. Son intelligible dans les deux sens. |
| Chat pendant ReplayKit | Invitation reçue via l’extension, visible au retour dans l’app. Les deux flux fonctionnent au premier plan sans arrêt mémoire/thermique. |
| Refus / attente 120 s | Aucun accès micro ; aucune réouverture automatique. Le technicien peut rester en attente et doit relancer Chat. |
| Micro refusé dans iPadOS | Échec compréhensible ; aucun son envoyé. Après modification de permission, nouvelle invitation nécessaire. |
| Couper / réactiver | L’indicateur suit l’état réel ; vérifier au poste technicien que la voix cesse puis reprend. |
| Fermer / Arrêter l’assistance | Fermer coupe uniquement la conversation ; arrêter l’assistance coupe aussi la diffusion. Sur réseau nominal, viser la coupure audio en ≤ 2 s et relever la mesure réelle. |
| App en arrière-plan / verrouillage / arrêt forcé | Microphone et lecture cessent, aucun retour automatique de l’appel. Un partage ReplayKit autorisé reste soumis à ses propres règles. |
| Coupure réseau / contrôle déconnecté / expiration | Fin de la conversation, pas de réutilisation de l’accord. Vérifier les délais réels de détection ; la limite de dix minutes ne se renouvelle pas. |
| Deux invitations / deux techniciens / arrêt tardif | Une seule invitation ou conversation locale ; aucun remplacement du technicien pendant l’accord ou l’appel. |
| Caméra / lien externe / téléchargement | Aucun accès caméra ; aucune sortie vers une page étrangère ou téléchargement depuis la fenêtre embarquée. Utiliser le transfert natif existant pour les documents. |
| Même Wi-Fi puis réseaux différents | Tester WebRTC direct puis relais TURN si configuré. Le succès du chat seul ne valide pas l’audio. |
| Haut-parleur / casque / Bluetooth / interruption audio système | Tester écho, intelligibilité, routage et récupération explicite. Documenter les combinaisons validées. |
| Rotation / texte agrandi / VoiceOver | Invitation, indicateur, commande muet et fermeture restent accessibles. |
| Compte sans Chat & Notify / certificat invalide | Invitation ou connexion refusée, sans contournement de permission/certificat. |

Effectuez cinq conversations successives, dont une atteignant la limite de durée.
Vérifiez la fin effective de l’indicateur microphone iPadOS après chaque fermeture,
le retour mémoire et l’absence de son après arrêt. Tout défaut de consentement,
de fermeture ou d’isolation bloque la validation. Les deux nouveaux XCTest et le
rendu/audio WebKit restent à exécuter ; aucun de ces résultats n’est présumé réussi.

Le [bilan technique](messenger-041.md) consigne les contrôles Windows réellement
passés. En cas d’échec, restaurez votre sauvegarde et recompilez ensemble app et
extension avec un Build adapté. Les archives antérieures sont conservées.
