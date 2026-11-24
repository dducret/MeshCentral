<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installer l’agent sur un iPad éloigné du Mac avec TestFlight

Guide du 20 novembre 2026 pour le projet **0.3.0 + hotfix1 AgentModel**, avec
la correction de l’identifiant de l’extension déjà appliquée dans votre Xcode.
L’abonnement Apple Developer actif permet d’envoyer un build depuis le Mac puis
de l’installer sur votre iPad par Internet. Aucun branchement USB, jumelage
Xcode, UDID ou réseau commun avec le Mac n’est nécessaire pour ce parcours.
Nous utilisons votre propre compte comme testeur interne.

## 1. Appliquer le petit complément sans refaire la configuration

Le ZIP `MeshCentral-iOS-0.3.0-TestFlight-update.zip` contient uniquement ces
fichiers nouveaux ou modifiés :

```text
apple/App/MeshCentralAssets.xcassets/Contents.json
apple/App/MeshCentralAssets.xcassets/MeshCentralAppIcon.appiconset/Contents.json
apple/App/MeshCentralAssets.xcassets/MeshCentralAppIcon.appiconset/Icon-1024.png
docs/testflight-ipad.md
docs/licensing.md
README.md
README-MAC.md
tools/generate_app_icon.py
tools/generate_xcode.py
tools/package_mac.py
```

Il apporte l’icône, sa source et sa licence, ce guide et la prise en charge des
assets dans les outils de maintenance. Il ne contient **ni projet `.xcodeproj`,
ni entitlements, ni fichiers de signature**. Aucune suppression ou modification
du code Rust/Swift n’est nécessaire. Les outils de maintenance sont fournis comme
sources ; **ne lancez pas `generate_xcode.py` sur votre projet configuré**.

Sur le Mac, décompressez ce ZIP dans un dossier temporaire. Copiez seulement
les fichiers indiqués aux mêmes emplacements dans votre dossier existant
`MeshCentral-iOS`, celui qui contient `Cargo.toml`. Ajoutez le dossier neuf
`MeshCentralAssets.xcassets` dans `apple/App`. Ne remplacez jamais les dossiers
`apple`, `App` ou le projet entier dans Finder. Conservez vos éventuelles
modifications personnelles des documents. Les anciennes empreintes de
`SHA256SUMS.json` décrivent le ZIP complet d’origine, pas cette mise à jour.

Dans Xcode, ouvrez **votre projet existant**, puis :

1. **File → Add Files to “MeshCentralIOS”…** ; sélectionnez le dossier
   `apple/App/MeshCentralAssets.xcassets` déjà copié dans votre projet.
2. Décochez **Copy items if needed** si le dossier est déjà à cet emplacement.
   Dans **Add to targets**, cochez uniquement **MeshCentralIOS**, pas l’extension
   ni les tests. Si le catalogue apparaît déjà, ne l’ajoutez pas une seconde fois.
3. Sélectionnez la cible **MeshCentralIOS → General → App Icons and Launch
   Screen → App Icons Source**, puis **MeshCentralAppIcon**.
4. Dans **Build Settings → All**, vérifiez **Primary App Icon Set Name**
   (`ASSETCATALOG_COMPILER_APPICON_NAME`) : `MeshCentralAppIcon`, en Debug
   **et Release**. Le catalogue doit figurer dans **Build Phases → Copy Bundle
   Resources** de l’app. Ne changez aucun identifiant ni réglage de signature.

Si vous avez déjà créé et configuré votre propre icône valide, gardez-la et
sa configuration. L’icône fournie est une création originale Apache-2.0.
Après un refus d’envoi signalant des icônes manquantes, le
[correctif des tailles d’icônes](testflight-icons-fix.md) ajoute explicitement
les tailles iPhone/iPad et conserve l’image App Store 1024 × 1024.
Les PNG sont RGB opaques ; le catalogue corrigé utilise le mode **All Sizes**.
[Documentation Apple sur les catalogues d’icônes](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

## 2. Vérifier le Mac et la signature pour appareil réel

Dans **Xcode → About Xcode**, vérifiez **Xcode 26 ou ultérieur** avec un SDK
iOS/iPadOS 26 ou ultérieur. Apple l’exige pour les uploads à App Store Connect
depuis le 28 avril 2026. Cela ne force pas à relever la version minimale
du projet, actuellement iOS/iPadOS 16.
[Exigence Apple](https://developer.apple.com/news/upcoming-requirements/?id=04282026a).

Dans **Signing & Capabilities**, vérifiez les cibles **MeshCentralIOS** et
**MeshCentralBroadcast**, y compris leur configuration **Release** :

- Même **Team**, correspondant à votre abonnement payant, et signature automatique.
- Conservez votre Bundle Identifier principal et votre valeur commune
  `MESH_HOST_BUNDLE_ID`. L’identifiant de l’extension doit être l’identifiant
  principal suivi de `.Broadcast`, comme dans la correction déjà appliquée.
- Les deux cibles doivent avoir accès au même **App Group**, normalement
  `group.<votre MESH_HOST_BUNDLE_ID>`, enregistré dans votre compte Apple.
  Gardez la même valeur que celle configurée dans ce projet.
- Le groupe de **Keychain Sharing** doit aussi être commun et autorisé par
  les profils. Les entitlements fournis utilisent
  `$(AppIdentifierPrefix)$(MESH_HOST_BUNDLE_ID)`.

Le simulateur ne vérifie pas les profils de distribution. L’App Group sert
aux échanges app/extension ; le trousseau commun transporte l’identité et
le consentement. Si Xcode signale un groupe absent du profil, vérifiez ces
capacités pour **les deux identifiants** dans votre compte Apple, puis laissez
la signature automatique actualiser les profils. Ne corrigez pas cette erreur
en supprimant les groupes.
[Configuration Apple des App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

## 3. Créer la fiche dans App Store Connect

Ouvrez [App Store Connect](https://appstoreconnect.apple.com/) avec le compte
de la même Team : **Apps → + → New App**.

| Champ | Valeur |
| --- | --- |
| Platforms | **iOS** ; cela inclut l’iPad |
| Name | Un nom disponible, par exemple `SDIC Assistance iOS` |
| Primary Language | Français |
| Bundle ID | L’identifiant exact de **MeshCentralIOS**, sans `.Broadcast` |
| SKU | Un identifiant interne unique, par exemple `sdic-assistance-ios-test` |

Si le Bundle ID n’est pas proposé, vérifiez qu’il est enregistré pour la même
Team dans **Certificates, Identifiers & Profiles → Identifiers**. Ne créez
pas une deuxième fiche pour l’extension. Le rôle Account Holder, Admin ou
App Manager permet la création de la fiche. Cette fiche doit exister avant
l’upload ; sa création ne publie pas l’app sur l’App Store.
[Création d’une fiche selon Apple](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

## 4. Archiver et envoyer le build depuis le Mac

1. Dans Xcode, sélectionnez le schéma **MeshCentralIOS**.
2. Remplacez le simulateur par **Any iOS Device (arm64)**, ou la destination
   générique iOS équivalente. Vous n’avez pas besoin de connecter l’iPad.
3. Choisissez **Product → Archive**. La compilation Release construit aussi
   le Rust pour appareil réel. Si la cible Rust manque, exécutez
   `rustup target add aarch64-apple-ios` dans Terminal sur le Mac.
4. Dans **Window → Organizer → Archives**, sélectionnez l’archive de l’app.
5. Choisissez **Distribute App → TestFlight Internal Only**. Selon la version
   de Xcode, l’option apparaît dans les réglages App Store Connect sous
   **TestFlight internal testing only**. Conservez la signature automatique.
6. Vérifiez le récapitulatif puis cliquez sur **Upload**.

Le numéro initial est version `0.3.0`, build `3`. Si ce build a déjà été envoyé,
utilisez un numéro supérieur pour l’app **et** l’extension, ou laissez Xcode
gérer les numéros avec **Manage version and build number** lorsqu’il le propose.
Gardez les versions de l’app et de son extension cohérentes.
Ce parcours réserve le build aux testeurs internes de votre équipe.
[Archivage et distribution Apple](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

## 5. Activer le build et vous inviter comme testeur interne

Dans la fiche **App Store Connect → TestFlight**, attendez la fin du traitement
du build ; la réussite de l’upload ne signifie pas qu’il est déjà installable.

Si **Missing Compliance / Conformité manquante** apparaît, ouvrez **Manage**
et répondez au questionnaire de chiffrement. Faits techniques de cette version :
HTTPS/WSS via URLSession ; clés, signatures RSA et SHA via Security/CryptoKit ;
pas de bibliothèque cryptographique tierce ajoutée ni d’algorithme cryptographique
maison. Le Rust traite le protocole et les formats. Ne répondez pas que l’app
n’utilise aucun chiffrement : elle en utilise via les API Apple. Suivez les
questions sur ces API et la distribution ; aucun indicateur d’exemption
`ITSAppUsesNonExemptEncryption` n’a été imposé dans ce complément.
[Questionnaire de conformité Apple](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).

Sous **Internal Testing / Tests internes**, cliquez sur **+**, créez le groupe
`Tests iPad`, puis **Add Builds** et sélectionnez le build traité. Si demandé,
indiquez dans **What to Test** : « Enrôlement, connexion MeshCentral, diffusion
ReplayKit dans Réglages après consentement, puis arrêt local du partage. »
Choisissez **Invite Testers** et ajoutez **votre propre utilisateur App Store
Connect**. Un simple destinataire e-mail extérieur à l’équipe n’est pas un
testeur interne. Le titulaire du compte est éligible ; vérifiez l’accès à l’app
si un autre utilisateur doit tester.
[Ajouter les testeurs internes](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

## 6. Installer sur l’iPad qui est avec vous

1. Sur l’iPad, installez **TestFlight**, l’application d’Apple, depuis l’App Store.
2. Ouvrez sur cet iPad l’e-mail d’invitation envoyé à votre compte testeur.
3. Touchez **View in TestFlight / Afficher dans TestFlight**, acceptez l’invitation,
   puis **Install / Installer**.
4. Ouvrez **MeshCentral**. L’application s’exécute maintenant sur votre iPad réel.

Ce parcours n’utilise ni TeamViewer sur l’iPad, ni installation d’un fichier IPA
dans Safari, ni mode développeur Xcode. Le build TestFlight expire après
90 jours ; les builds suivants se mettent à jour depuis TestFlight.
[Fonctionnement de TestFlight](https://developer.apple.com/testflight/),
[durée de disponibilité des builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

## 7. Tester la connexion et l’écran de Réglages

1. Dans l’agent sur l’iPad, donnez un nom distinct, par exemple `iPad test SDIC`,
   puis collez votre lien d’invitation MeshCentral. Il n’est pas inclus dans
   les fichiers. Choisissez **Lire l’invitation**, vérifiez le serveur,
   puis **Enregistrer l’enrôlement → Se connecter**.
2. Vérifiez l’apparition de cet iPad dans MeshCentral. Son identité est distincte
   de celle du simulateur. L’iPad doit pouvoir joindre votre serveur HTTPS/WSS.
3. Sur l’iPad, touchez **Préparer le partage de l’écran**, puis le bouton système
   de diffusion et **Lancer la diffusion** pour **MeshCentral Screen**.
   Le microphone reste désactivé. Restez dans l’app pendant la connexion.
4. Depuis MeshCentral, ouvrez le bureau de cet iPad et connectez le visualiseur,
   ou utilisez votre panneau `ios-assist.html` déjà installé. Fermez une autre
   session de visualisation éventuelle. Sur l’iPad, touchez
   **Autoriser cette assistance** pour le technicien attendu.
5. Quand l’image apparaît, revenez à l’écran d’accueil de l’iPad puis ouvrez
   **Réglages**. Faites défiler une page : le critère de réussite est une image
   qui continue à se mettre à jour alors que l’agent n’est plus au premier plan.
6. Arrêtez la diffusion depuis le contrôle système iPadOS ou revenez dans l’agent
   et touchez **Arrêter la diffusion**. Vérifiez que la transmission cesse.

L’extension ReplayKit possède sa propre connexion pendant la diffusion.
L’arrêt de la connexion ordinaire de l’app en arrière-plan est attendu.
La diffusion complète reste **à vérifier sur votre iPad** : les essais précédents
portaient seulement sur la fenêtre de l’agent dans le simulateur. La session
est limitée à dix minutes ; une interruption demande un nouveau consentement.
Le partage reste en lecture seule, sans contrôle tactile distant. Certains
contenus protégés peuvent être masqués par iPadOS.

Si le test échoue, relevez l’étape précise, la version d’iPadOS et le message
affiché ; utilisez le diagnostic de connexion dans l’app. Évitez d’inclure
votre lien d’invitation dans les captures ou journaux partagés.

## Vérifications de ce complément

Icône et catalogue contrôlés sous Windows, structure du projet et contenu
incrémental vérifiés. Aucun ajout de dépendance. L’icône, les fichiers JSON,
les outils et ce document sont sous Apache-2.0 ; voir `LICENSE` et
`docs/licensing.md`. L’archive complète précédente et le hotfix sont conservés.
L’archivage Xcode, la signature, l’upload Apple et le test physique ne sont pas
exécutables dans cet environnement Windows ; ils restent à réaliser sur le Mac
et l’iPad selon les étapes ci-dessus.
