<!-- SPDX-License-Identifier: Apache-2.0 -->
# Récupération des huit fichiers Swift 0.4.4

Ce complément répond au signalement d'une copie du projet contenant la
documentation/tests 0.4.4 avec des sources Swift antérieures. Le 22 novembre 2026,
le contrôle du dossier Windows `C:\Development\MeshCentral\ios-agent` a trouvé
les 140 fichiers conformes au manifeste original, dont les huit Swift concernés.
Le ZIP original, sa copie extraite et le snapshot contiennent ces mêmes huit
Swift. Le champ natif **Votre message** de `MessengerConversationView` est présent
dans `apple/App/Sources/AssistanceView.swift`, avec le bouton **Envoyer**.

L'écart n'a donc pas été reproduit dans ce dossier. La copie différente et son
chemin ne sont pas identifiés ici. L'ancienne livraison 0.4.3 n'est plus disponible
localement : l'affirmation « sept fichiers identiques à 0.4.3 » n'a pas pu être
contrôlée indépendamment. L'utilisateur a précisé qu'il n'y a pas de correction
locale à conserver. Aucun Swift du dossier Windows n'a été réécrit.

## Contenu et base

`MeshCentral-iOS-0.4.4-swift-recovery.zip` reprend exactement les huit fichiers
Swift du ZIP original vérifié, ajoute un vérificateur autonome et cette procédure.
Ces huit fichiers sont volontairement renvoyés pour réparer une copie incomplète.
La version reste **0.4.4** ; aucune nouvelle fonctionnalité n'est ajoutée.

Base : projet ayant reçu le complément 0.4.4, éventuellement incomplet côté Swift.
ZIP original : `MeshCentral-iOS-0.4.4-ipad-chat-ui-update.zip`, SHA-256
`7e7d6df0e60e637752ec88896be6b594c77ef6aa7dbdfbb4880f13f419a05a5b`.
Si votre projet est encore entièrement en 0.4.3, appliquez d'abord le complément
original avec [sa procédure](ipad-chat-044-update-fr.md).

Aucun projet Xcode, plist, entitlement, XCFramework, serveur ou plugin n'est
fourni. Aucun fichier à supprimer ou renommer. Les archives et manifests antérieurs
sont conservés ; nouvelle référence : `dist/ipad-chat-044-recovery-delivery.json`.

## Appliquer sur le Mac

1. Arrêtez la diffusion et sauvegardez le projet existant. Dans Xcode, sélectionnez
   `AssistanceView.swift`, puis regardez **File Inspector → Full Path**. C'est ce
   dossier de sources qu'il faut mettre à jour. La racine utilisée ci-dessous
   contient `apple/` et `Cargo.toml`, pas seulement le fichier `.xcodeproj`.
2. Décompressez le paquet de récupération. Depuis son dossier racine, contrôlez
   les fichiers reçus :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   for name, checksum in json.loads(pathlib.Path('SHA256SUMS-0.4.4-recovery.json').read_text()).items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum, name
   print('Paquet conforme')
   PY
   ```

3. Avant la copie, contrôlez le projet réellement ouvert dans Xcode :

   ```sh
   python3 tools/check_ipad_chat_044_delivery.py --root "/chemin/du/projet/MeshCentral-iOS"
   ```

   Le script affiche le chemin vérifié et les huit résultats. `DIFFERENT` signifie
   des octets différents, sans conclure à une ancienne version ; `MISSING` indique
   un fichier absent ou un mauvais dossier. Le script ne modifie rien.
4. Copiez les fichiers du paquet dans cette racine en **fusionnant les dossiers**
   et en remplaçant seulement les fichiers fournis. Depuis le dossier du paquet :

   ```sh
   rsync -av ./ "/chemin/du/projet/MeshCentral-iOS/"
   ```

   N'utilisez pas `--delete` et ne remplacez pas tout le dossier `apple/`.
   Team, Bundle IDs, App Groups, Keychain, profils et préférences restent dans
   votre projet configuré. Ne lancez pas `generate_xcode.py`.
5. Relancez le contrôle de l'étape 3 : résultat attendu **PASS: 8/8**. Il vérifie
   les sources à destination, indépendamment de leur documentation et sans avoir
   besoin des anciens ZIP. Si les huit fichiers sont conformes mais l'interface
   reste ancienne, vérifiez à nouveau le **Full Path** utilisé par Xcode, puis la
   cible et le Build effectivement installés.
6. Gardez Marketing Version **0.4.4**, choisissez un même nouveau Build pour
   l'app et l'extension. Conservez le XCFramework **0.4.2**. Faites **Clean Build
   Folder**, **Product → Test**, compilez les deux cibles et réinstallez sur l'iPad.

## Contrôles avant livraison

Les deux tests Messenger Windows passent sur les scripts Swift réellement livrés,
y compris l'envoi via `xsend`, les limites et le refus microphone. Le contrôle
de livraison et ses tests vérifient les fichiers manquants, modifiés, une version
affichée ancienne, un mauvais dossier et l'absence d'écriture. Le paquet doit
également passer `tools/package_ipad_chat_044_recovery.py --verify` sur le poste
de préparation, avec le ZIP/snapshot 0.4.4 original conservé.

La compilation Swift, XCTest, WebKit, le clavier et l'audio ne sont pas exécutables
ici. Sur iPad, reprendre [les validations 0.4.4](ipad-chat-044-update-fr.md) :
accueil simplifié, **Votre message** et **Envoyer** visibles, échange dans les deux
sens, microphone autorisé/refusé, arrêt et arrière-plan, partage ReplayKit.
Un contrôle d'empreintes réussi ne valide pas ces comportements sur appareil.
