<!-- SPDX-License-Identifier: Apache-2.0 -->
# Correctif incrémental : icônes iPhone/iPad pour TestFlight

Date : 20 novembre 2026. Base : **0.3.0 + hotfix1 + complément
`MeshCentral-iOS-0.3.0-TestFlight-update.zip`** déjà appliqués.

Le précédent catalogue déclarait une seule image universelle 1024 × 1024 et
comptait sur sa déclinaison automatique par Xcode. La capture du refus d’envoi
confirme l’absence des icônes **iPhone 120 × 120** et **iPad 152 × 152** dans
le bundle. Ce correctif déclare et fournit ces tailles et les autres variantes
explicitement. Sans l’archive compilée, l’intégration du catalogue sur le Mac
reste à vérifier. Vérifiez aussi l’inclusion du catalogue dans la cible
Release : des PNG présents sur disque mais absents de l’app archivée ne
résolvent pas un refus d’upload.

## Contenu du ZIP

`MeshCentral-iOS-0.3.0-TestFlight-icons-fix.zip` contient seulement :

- Dans `apple/App/MeshCentralAssets.xcassets/MeshCentralAppIcon.appiconset/` :
  `Contents.json` modifié et 12 nouveaux fichiers `Icon-N.png`, où N vaut
  **20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167 et 180**.
- `tools/generate_app_icon.py`, mis à jour pour reproduire toutes ces tailles.
- `docs/licensing.md` et `docs/testflight-ipad.md`, mis à jour.
- Ce guide `docs/testflight-icons-fix.md`.

**Conservez `Icon-1024.png` déjà présent** : il reste inchangé et n’est donc
pas inclus dans ce ZIP. Aucune suppression, aucun renommage, aucune modification
de Team, de Bundle ID, d’App Group, d’entitlements ou de projet Xcode.
Les PNG sont opaques, RGB 8 bits sRGB, carrés, sans masque de coins incorporé.
L’illustration et toutes ses tailles sont originales, sous Apache-2.0.
Aucune dépendance ajoutée.

## Application sur le Mac

1. Décompressez le nouveau ZIP dans un dossier temporaire.
2. Dans votre projet **existant**, ouvrez le dossier
   `apple/App/MeshCentralAssets.xcassets/MeshCentralAppIcon.appiconset/`.
   Copiez-y les **12 PNG et le fichier Contents.json** du correctif. Remplacez
   seulement ce `Contents.json`. **Ne remplacez pas le dossier entier** dans
   Finder : cela risquerait de retirer l’image 1024 conservée de la version
   précédente. Copiez aussi les quatre fichiers de documentation/outillage
   à leurs emplacements respectifs. Aucun outil n’a besoin d’être exécuté.
3. Ouvrez votre projet Xcode configuré. Dans le catalogue
   **MeshCentralAssets → MeshCentralAppIcon**, vérifiez le mode iOS **All Sizes**
   et les images présentes. Si Xcode affiche encore l’ancien catalogue,
   fermez puis rouvrez le projet. N’ajoutez pas les PNG individuellement à
   Copy Bundle Resources : c’est le catalogue `.xcassets` qui doit être compilé.
4. Dans la cible **MeshCentralIOS → Build Settings → All**, cherchez
   **Primary App Icon Set Name** (`ASSETCATALOG_COMPILER_APPICON_NAME`).
   La valeur doit être **MeshCentralAppIcon**, surtout en **Release**.
5. Dans **MeshCentralIOS → Build Phases → Copy Bundle Resources**, vérifiez
   la présence de **MeshCentralAssets.xcassets**. S’il manque, utilisez le
   bouton **+** pour ajouter ce catalogue existant à la cible principale.
   S’il n’apparaît pas du tout dans le navigateur Xcode, utilisez
   **File → Add Files**, choisissez ce catalogue dans votre projet existant,
   décochez **Copy items if needed** et cochez seulement la cible MeshCentralIOS.
6. Faites **Product → Clean Build Folder** (`⇧⌘K`), sélectionnez
   **Any iOS Device (arm64)** puis **Product → Archive**.
   Choisissez **la nouvelle archive** dans Organizer : l’ancienne archive
   ne contient pas le correctif. Si le numéro de build a déjà été accepté
   par Apple, utilisez le suivant pour l’app et son extension.
7. Reprenez **Distribute App → TestFlight Internal Only → Upload**.

Le projet cible iPhone **et** iPad. Le catalogue couvre les emplacements
suivants, selon le [format Apple des icônes](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html) :

| Appareil / emplacement | Points | Échelles | Pixels |
| --- | --- | --- | --- |
| iPhone, notifications | 20 | 2x / 3x | 40 / 60 |
| iPhone, Réglages | 29 | 2x / 3x | 58 / 87 |
| iPhone, recherche | 40 | 2x / 3x | 80 / 120 |
| iPhone, accueil | 60 | 2x / 3x | 120 / 180 |
| iPad, notifications | 20 | 1x / 2x | 20 / 40 |
| iPad, Réglages | 29 | 1x / 2x | 29 / 58 |
| iPad, recherche | 40 | 1x / 2x | 40 / 80 |
| iPad, accueil | 76 | 1x / 2x | 76 / 152 |
| iPad Pro, accueil | 83,5 | 2x | 167 |
| App Store | 1024 | 1x | 1024, déjà fourni |

Plusieurs emplacements utilisent le même PNG : **18 emplacements, 13 fichiers**.
[Réglage Apple de l’icône principale](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

## Si l’envoi refuse encore les icônes

Copiez le message exact, avec son code ITMS et le nom du bundle concerné.
Dans Organizer, sélectionnez la **nouvelle** archive puis **Show in Finder**.
Sur son fichier `.xcarchive`, faites **Show Package Contents** et ouvrez
`Products/Applications/MeshCentralIOS.app` avec **Show Package Contents**.
Il faut examiner cette app compilée, pas le `Info.plist` source.

Dans son `Info.plist`, vérifiez les dictionnaires `CFBundleIcons` et
`CFBundleIcons~ipad` ainsi que `CFBundlePrimaryIcon` et le nom d’icône.
Le journal de compilation doit montrer le catalogue compilé avec
`--app-icon MeshCentralAppIcon`. Des clés d’icônes absentes ou un catalogue
non compilé indiquent un problème d’intégration dans la cible Release.
Laissez Xcode produire ces clés : ne les ajoutez pas à la main pour masquer
l’absence des images. En cas de refus citant `MeshCentralBroadcast.appex`,
transmettez ce détail ; cette extension de diffusion n’est pas la cible
principale à laquelle on ajoute le catalogue.

## Vérification effectuée

Sous Windows : dimensions et format RGB de tous les PNG, intégrité de leur
encodage, correspondance des fichiers avec les 18 emplacements du catalogue,
présence des images d’accueil et App Store, licences et contenu incrémental.
Le PNG 1024, le projet Xcode et les paramètres de signature sont inchangés.
Il n’y a pas de code Rust/Swift modifié. La compilation `actool` dans Xcode,
l’archive Apple et son acceptation TestFlight restent à vérifier sur le Mac.
