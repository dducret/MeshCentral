<!-- SPDX-License-Identifier: Apache-2.0 -->
# iPad : accueil simplifié et conversation — 0.4.4

Ce complément source apporte un accueil centré sur **Démarrer l’assistance**,
un menu **Options**, un champ de message natif et l’état réel du chat/microphone.
Il corrige les comparaisons d’URL trop strictes et les échecs silencieux d’ouverture.
Le fonctionnement complet sur votre iPad reste à valider après compilation.

Si les documents sont à jour mais les huit Swift restent anciens, utilisez
[le complément de récupération et son contrôle du dossier Xcode](ipad-chat-044-recovery-fr.md).

## Installation sur votre projet existant

1. Sauvegardez le projet et arrêtez toute diffusion. Base requise :
   `MeshCentral-iOS-0.4.3-chat-fix-update.zip`, SHA-256
   `9e4bff1b3e63458c91ee0166e30af35bf1a0c9211f3f047ce959d657dbb735c9`.
   Appliquez [la 0.4.3](chat-043-update-fr.md) d’abord si nécessaire.
2. Décompressez `MeshCentral-iOS-0.4.4-ipad-chat-ui-update.zip`. Dans son dossier :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   for name, checksum in json.loads(pathlib.Path('SHA256SUMS-0.4.4.json').read_text()).items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum, name
   print('Empreintes conformes')
   PY
   ```

3. Comparez puis fusionnez les fichiers fournis dans votre projet existant,
   à la racine contenant Cargo.toml. Exemple avec le chemin adapté :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Préservez les changements locaux ; pas de `--delete`. Aucun fichier à
   supprimer/renommer, aucun serveur/plugin à remplacer.
4. Dans Xcode, mettez **Marketing Version à 0.4.4** pour l’app et l’extension,
   Debug et Release, et choisissez un même nouveau Build. Gardez Team, Bundle IDs,
   App Groups, Keychain, profils, entitlements et préférences. Aucun projet/plist
   configuré n’est livré. Ne lancez pas `generate_xcode.py`.
5. Conservez **MeshCore.xcframework de la 0.4.2** : Rust/ABI inchangés. Vérifiez
   la description microphone ajoutée avec la 0.4.1. Faites Clean Build Folder,
   Product → Test, compilation des deux cibles, puis installation sur l’iPad.
   Validez l’archive signée et les déclarations de confidentialité avant toute
   distribution. La documentation Apple actuelle marque le sélecteur ReplayKit
   historique comme déprécié : contrôlez les avertissements du SDK réellement
   utilisé et le partage sur votre iPad. Cette mise à jour conserve ce sélecteur.

## Accueil épuré

Après l’enrôlement, l’écran principal propose **Démarrer l’assistance**. La roue
dentée **Options** regroupe les détails de connexion, le chat sans partage,
les outils avancés et le changement d’enrôlement.

Pour le partage d’écran : **Démarrer l’assistance → toucher le bouton de diffusion
Apple → confirmer « Lancer la diffusion » dans iPadOS**. Il reste donc plusieurs
gestes, avec une action principale à chaque étape. Le bouton d’arrêt reste visible.
Le démarrage donne l’accord au premier technicien habilité, pour dix minutes au
maximum ; l’envoi d’un document ou d’une capture conserve sa confirmation.

## Vérifier le chat avant le partage

1. **Options → Se connecter pour le chat uniquement**, puis revenez à l’accueil.
   Gardez l’app au premier plan. Sur le site, ouvrez la fiche du bon iPad,
   vérifiez la version 0.4.4 et cliquez **Chat**. Acceptez dans le bandeau iPad.
2. Vérifiez les états affichés : chargement, attente du technicien, puis connexion.
   **L’acceptation locale ne signifie plus que la liaison est déjà connectée.**
   La zone de conversation doit occuper l’espace disponible et **Votre message**
   rester visible en bas. **Envoyer** reste désactivé tant que le chat n’est pas lié.
3. Envoyez un message dans chaque sens. Vérifiez accents/emoji, clavier ouvert,
   portrait/paysage, texte agrandi et vue partagée. Au-delà de 4096 octets, l’app
   demande de raccourcir le message. Un échec d’envoi doit conserver le brouillon ;
   il n’y a pas de renvoi automatique. Fermer la conversation efface le brouillon.
4. Quand l’audio est prêt, touchez **Activer le microphone**. Autorisez iPadOS,
   vérifiez l’indicateur microphone, puis testez les deux sens, couper/réactiver.
   Le technicien active aussi son microphone. Un refus iPadOS doit être indiqué.
   Si vous passez dans Réglages pour modifier la permission, la conversation se
   ferme : revenez puis demandez une nouvelle invitation Chat.
5. Si le texte fonctionne mais que l’audio attend WebRTC, vérifier le chemin
   réseau et la configuration STUN/TURN existante du serveur. L’app ne prétend pas
   avoir activé le micro et ne remplace pas ces réglages réseau.
6. Une page bloquée ou muette doit désormais produire un état puis un bandeau
   d’erreur, au lieu d’un bouton sans effet. Si le serveur affiche encore un refus,
   notez son texte exact, celui de l’iPad, la version du serveur, iPadOS et le Build.
   Ne transmettez pas de lien contenant `auth=`, ni d’identifiant de session.
   Ne désactivez jamais TLS pour résoudre une erreur de page/relais.

## Validation du parcours simplifié

- Accueil : un bouton principal, Options disponible, aucun réglage technique
  imposé au démarrage. Annuler la préparation puis recommencer exige un nouvel accord.
- Partage : confirmation système, attente/nom du technicien, arrêt et limite de
  temps restent visibles. Les Options et la conversation gardent le bouton d’arrêt.
- Chat pendant ReplayKit : accepter depuis l’app, écrire/parler puis arrêter.
  Le passage en arrière-plan ferme toujours le chat vocal, sans relance automatique.
- Interruption : fermer le technicien, couper le réseau ou arrêter localement.
  Le statut devient déconnecté ; aucune ancienne réponse JavaScript ne réactive
  le micro. Reconnexion uniquement sur nouvelle invitation et nouvel accord.
- Vérifier l’inventaire matériel, les étapes de guidage, documents/captures
  consentis et leurs contrôles accessibles depuis Options.

Les tests Windows de protocole/scripts passent ; Swift/Xcode, mise en page réelle,
clavier et audio iPad ne sont pas vérifiés ici. Gardez la sauvegarde 0.4.3 pour un
retour arrière en reconstruisant ses deux cibles, sans effacer l’enrôlement.
