<!-- SPDX-License-Identifier: Apache-2.0 -->
# Correctif TestFlight : mode de traitement ReplayKit

Date : 20 novembre 2026. Base : version 0.3.0 avec hotfix1, complément
TestFlight et correctif des icônes déjà appliqués.

Le refus affiché concerne `MeshCentralBroadcast.appex` et indique que
`RPBroadcastProcessMode` n’est pas spécifié. Le fichier fourni déclarait cette
clé dans `NSExtension → NSExtensionAttributes`. Le correctif la déplace
directement dans `NSExtension`, à côté de `NSExtensionPrincipalClass`.
Sa valeur reste la chaîne `RPBroadcastProcessModeSampleBuffer`.

Apple décrit cette valeur pour
[RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler).
La structure directe sous `NSExtension` est également visible dans le
[projet de référence maintenu par HaishinKit](https://github.com/HaishinKit/HaishinKit.swift/blob/main/Examples/iOS/Screencast/Info.plist).
Ces sources ont été consultées pour vérifier la configuration ; aucun SDK,
code tiers ou dépendance n’est ajouté au projet.

## Fichiers du ZIP incrémental

- `apple/Broadcast/Info.plist.patch` : déplacement ciblé de la clé.
- `tools/generate_xcode.py` : générateur corrigé pour les prochains projets.
- `tools/package_mac.py` : vérification de la position de cette clé.
- `docs/testflight-broadcast-plist-fix.md` : ce guide.

Le ZIP ne remplace ni votre fichier Info.plist complet, ni votre projet Xcode.
Il ne contient pas d’entitlements ou de réglages de signature. Team, Bundle ID,
App Groups, trousseau et icônes restent ceux que vous avez configurés.
Aucun fichier à supprimer ou renommer. **Ne relancez pas generate_xcode.py**
sur le projet configuré : c’est un outil de maintenance, pas l’application
de ce correctif. Les fichiers originaux du correctif sont sous Apache-2.0.

## Appliquer le patch sur le Mac

1. Décompressez le ZIP dans un dossier temporaire.
2. Copiez uniquement ses quatre fichiers aux mêmes emplacements dans votre
   dossier de projet existant. Ne remplacez aucun dossier entier dans Finder.
3. Fermez le projet dans Xcode pour appliquer le changement sur disque.
4. Ouvrez Terminal et placez-vous dans le dossier qui contient `Cargo.toml`,
   `apple` et `tools`. Astuce : saisissez `cd `, glissez ce dossier depuis
   Finder dans Terminal, puis appuyez sur Entrée.
5. Exécutez ces deux commandes :

```sh
cp -pn apple/Broadcast/Info.plist apple/Broadcast/Info.plist.before-process-mode-fix
patch -N -p1 < apple/Broadcast/Info.plist.patch
```

La première conserve une sauvegarde locale sans écraser une sauvegarde déjà
présente. La seconde modifie seulement les lignes concernées. Si le patch
affiche `FAILED`, ne forcez pas son application : utilisez la correction
manuelle ci-dessous. S’il est déjà appliqué, vérifiez simplement la structure.

6. Vérifiez le résultat avec les outils intégrés à macOS :

```sh
/usr/bin/plutil -lint apple/Broadcast/Info.plist
/usr/libexec/PlistBuddy -c 'Print :NSExtension:RPBroadcastProcessMode' apple/Broadcast/Info.plist
```

Le premier doit indiquer `OK`, le second `RPBroadcastProcessModeSampleBuffer`.

## Correction manuelle équivalente dans Xcode 26.1.1

Si vous préférez modifier les deux lignes vous-même :

1. Ouvrez le fichier **Info.plist de Broadcast**, pas celui de l’application.
   Depuis Finder, le chemin est `apple/Broadcast/Info.plist`.
2. Dans le navigateur Xcode, faites un clic droit sur ce fichier puis
   **Open As → Source Code**.
3. À l’intérieur de `NSExtension`, retirez uniquement ce bloc :

```xml
<key>NSExtensionAttributes</key>
<dict>
    <key>RPBroadcastProcessMode</key>
    <string>RPBroadcastProcessModeSampleBuffer</string>
</dict>
```

Si votre `NSExtensionAttributes` contient d’autres clés personnelles, gardez
ce dictionnaire et retirez seulement la paire `RPBroadcastProcessMode` / valeur.

4. Toujours **à l’intérieur du dictionnaire NSExtension**, après la valeur de
   `NSExtensionPrincipalClass`, ajoutez :

```xml
<key>RPBroadcastProcessMode</key>
<string>RPBroadcastProcessModeSampleBuffer</string>
```

La hiérarchie attendue est :

```text
NSExtension
  NSExtensionPointIdentifier = com.apple.broadcast-services-upload
  NSExtensionPrincipalClass  = $(PRODUCT_MODULE_NAME).SampleHandler
  RPBroadcastProcessMode    = RPBroadcastProcessModeSampleBuffer
```

Conservez les autres valeurs du fichier. N’ajoutez pas cette clé à la racine
du plist de l’app principale ni comme entitlement. Enregistrez avec `⌘S`.

## Recréer l’archive à envoyer

Rouvrez votre projet configuré. Pour la cible **MeshCentralBroadcast**, vérifiez
dans **Build Settings → All → Packaging → Info.plist File** que la configuration
Release utilise bien `../Broadcast/Info.plist` pour ce projet.

Faites **Product → Clean Build Folder**, sélectionnez le schéma **MeshCentralIOS**
et **Any iOS Device (arm64)**, puis **Product → Archive**. Envoyez la **nouvelle**
archive avec **TestFlight Internal Only**. Si Apple a déjà accepté le numéro
de build, utilisez le suivant en conservant le même numéro pour l’app et
l’extension.

Si le même refus apparaît encore, contrôlez le fichier compilé : dans Organizer,
**Show in Finder** sur la nouvelle archive, puis **Show Package Contents** sur
le `.xcarchive`. Le fichier concerné est
`Products/Applications/MeshCentralIOS.app/PlugIns/MeshCentralBroadcast.appex/Info.plist`.
Il doit contenir la clé sous `NSExtension`. Ne modifiez pas l’archive signée ;
si la clé manque, il faut corriger le fichier source/configuration réellement
utilisé, puis reconstruire.

## Validation et portée

Sous Windows : lecture du plist corrigé, contrôle du déplacement unique de la
clé, conservation de toutes les autres valeurs, vérification du générateur
dans un dossier isolé, validation structurelle du projet, licences et ZIP
incrémental. Aucun code Rust/Swift modifié. Xcode, la signature, la validation
Apple et le test sur iPad restent à exécuter sur le Mac et l’appareil.

Le serveur de référence reste à la révision
`67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Le HEAD officiel observé est maintenant
`ca24e0f5e95749568ac0af91e59125a71aa6ff2f` ; le fetch et la création de branche
locale sont bloqués par les droits d’écriture de `.git`. Aucun changement
amont ni serveur n’a été intégré à ce correctif d’empaquetage iOS.
