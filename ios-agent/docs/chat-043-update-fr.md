<!-- SPDX-License-Identifier: Apache-2.0 -->
# Correctif Chat iPad — 0.4.2 vers 0.4.3

Ce complément source rend l’invitation Chat visible dans un bandeau en haut de
l’app et affiche une raison si elle est rejetée. Il corrige aussi le cas d’un
nom complet de technicien vide et accepte les deux formes de commande openUrl
reconnues par l’agent MeshCentral. **La cause exacte sur l’iPad signalé n’a pas
encore été confirmée ; compilation et validation Apple restent nécessaires.**

## Installation incrémentale

1. Partez de votre projet 0.4.2 installé, sauvegardez-le et arrêtez la diffusion.
   Base : `MeshCentral-iOS-0.4.2-hardware-inventory-update.zip`, SHA-256
   `1c3b4b84fadc132918421ab8c7c2a07d4ae1db2a0407e0ba46d027ed62870b49`.
2. Décompressez `MeshCentral-iOS-0.4.3-chat-fix-update.zip`. Depuis son dossier :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   for name, checksum in json.loads(pathlib.Path('SHA256SUMS-0.4.3.json').read_text()).items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum, name
   print('Empreintes conformes')
   PY
   ```

3. Comparez puis fusionnez les fichiers fournis dans votre projet existant, à la
   racine contenant Cargo.toml. Exemple, en adaptant le chemin :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Préservez vos modifications locales ; pas de `--delete`. Aucun fichier à
   supprimer/renommer, aucun serveur/plugin à remplacer. Ne lancez pas
   `generate_xcode.py`.
4. Dans Xcode, réglez **Marketing Version à 0.4.3** pour l’app et l’extension,
   Debug et Release, avec un même nouveau Build. Gardez Team, identifiants,
   App Groups, Keychain, profils et préférences. Le projet/plist/entitlements
   configurés sont exclus du ZIP. Conservez **MeshCore.xcframework de la 0.4.2** :
   le Rust et l’ABI ne changent pas dans ce correctif.
5. Vérifiez que la clé microphone de [l’installation 0.4.1](messenger-041-update-fr.md)
   existe dans le plist de l’app ; conservez son texte local. Aucun nouvel accès
   caméra ni mode d’arrière-plan. Faites Clean Build Folder, Product → Test,
   puis reconstruisez et installez ensemble l’app et l’extension. Validez aussi
   l’archive/signature et les déclarations de confidentialité de votre projet
   avant toute distribution. Aucun envoi App Store/TestFlight n’est effectué ici.

## Essai prioritaire

1. Gardez l’app iPad au premier plan, puis touchez **Se connecter**. Vérifiez que
   l’agent sur le site annonce 0.4.3. Depuis la fiche de **cet iPad**, cliquez Chat.
2. Un bandeau **Invitation Chat** doit apparaître en haut, même si la page est
   descendue ou si l’écran d’assistance est ouvert. Touchez **Ouvrir la conversation**.
   La page Messenger s’ouvre ; le microphone demande toujours votre action et
   votre autorisation. Testez aussi Refuser et une nouvelle invitation.
3. Si **Invitation Chat bloquée** apparaît, relevez seulement son message :

   | Message | Vérification |
   | --- | --- |
   | Serveur, port ou chemin différent | Comparer l’adresse d’enrôlement et l’adresse publique HTTPS configurée sur MeshCentral, y compris alias/port. Ne pas désactiver TLS ni changer d’identité pour contourner le refus. |
   | Droits absents/invalides | Contrôler Chat & Notify et le droit de routage distant du compte concerné. |
   | Identité/appareil/domaine invalide | Vérifier la fiche iPad sélectionnée, le domaine et la connexion active. |
   | Lien invalide | Faire vérifier la commande serveur ; ne pas coller le lien authentifié du navigateur du technicien dans l’iPad. |
   | Configuration microphone manquante après Ouvrir | Appliquer seulement la clé de description microphone documentée en 0.4.1, puis reconstruire l’app. |

4. Si aucun bandeau n’apparaît en 0.4.3, vérifier que la connexion est active,
   attendre cinq secondes et réessayer. Contrôler côté serveur les droits et le
   mode LAN-only : ce mode peut empêcher l’envoi de l’invitation par MeshCentral.
   Relever version du serveur, Version/Build de l’app, écran utilisé et présence
   ou non du bandeau. Ne pas transmettre de lien comportant un paramètre auth.

## Non-régression avant livraison

- Essayer portrait/paysage, texte agrandi, page descendue et navigation Assistance.
- Pendant une diffusion ReplayKit, recevoir Chat puis revenir dans l’app : une
  invitation encore valide doit être proposée ; un refus doit afficher son motif.
- Vérifier qu’une invitation expirée, un arrêt, une déconnexion ou un passage en
  arrière-plan ne relance pas une conversation ni le microphone.
- Fermer le bandeau d’erreur : il ne doit pas réapparaître à chaque lecture de
  l’état de l’extension. Un nouveau clic Chat peut produire une nouvelle demande.
- Vérifier texte/audio Messenger au premier plan, arrêt local du partage et
  inventaire Détails confirmé avec la 0.4.2.

Les tests Windows passent sur les protocoles et les sources indiquées dans
[le dossier technique](chat-043.md). Swift/XCTest, rendu du bandeau et conversation
réelle sur iPad n’ont pas été vérifiés ici. Conservez la sauvegarde 0.4.2 pour un
retour arrière en reconstruisant ses deux cibles, sans effacer l’enrôlement.
