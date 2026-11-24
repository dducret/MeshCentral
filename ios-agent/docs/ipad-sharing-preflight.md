<!-- SPDX-License-Identifier: Apache-2.0 -->
# iPad connecté : erreur « Paramètres invalides » à la préparation du partage

Correctif du 20 novembre 2026 pour la version 0.3.0 installée par TestFlight,
après hotfix1, le complément TestFlight, les icônes et le patch ReplayKit.
L’utilisateur a confirmé l’installation sur un iPad réel et la connexion
initiale à MeshCentral. Le démarrage ReplayKit n’est pas encore validé.

## Cause identifiée dans le code

Le bouton « Préparer le partage de l’écran » fermait la connexion ordinaire,
puis accédait au conteneur **App Group** pour nettoyer les échanges temporaires.
Si ce conteneur était inaccessible, l’app affichait le même message que pour
une configuration WSS invalide. La réussite de la connexion initiale ne valide
pas l’accès à ce conteneur, qui n’est utilisé qu’au début du partage.

L’utilisateur confirme que le même groupe est coché dans les deux cibles.
Il reste à vérifier que la valeur `MeshCentralAppGroup` des Info.plist compilés
correspond exactement à ce groupe et qu’il figure dans les deux signatures.
Un nom non résolu ou différent de celui autorisé par la signature reste une
cause possible. Sans examiner le build signé sur le Mac, le cas précis ne peut
pas être confirmé.
Le groupe de trousseau est une autre configuration vérifiée pendant cette phase.
Conservez l’enrôlement et l’adresse WSS qui permettent déjà la connexion.

## Vérifier les deux cibles dans Xcode 26.1.1

1. Ouvrez **votre projet existant**, appuyez sur `⌘1`, puis cliquez sur le projet
   bleu **MeshCentralIOS** en haut de la liste des fichiers.
2. Sous **TARGETS**, choisissez **MeshCentralIOS** puis **Signing & Capabilities**.
   Vérifiez les réglages **Release**, utilisés pour l’archive TestFlight ;
   utilisez **All** si vous voulez appliquer la même capacité à Debug et Release.
3. Repérez la capacité **App Groups**. Si elle manque, cliquez sur
   **+ Capability**, recherchez **App Groups** et ajoutez-la.
4. Cochez le groupe commun destiné à cette application. S’il existe déjà dans
   votre compte, sélectionnez-le. N’en créez pas un nouveau à chaque build.
5. Refaites les étapes 2 à 4 pour **MeshCentralBroadcast**, en utilisant
   **exactement le même groupe** et la même Team.
6. Comparez la valeur `MeshCentralAppGroup` dans les **deux** Info.plist :
   `apple/App/Info.plist` et `apple/Broadcast/Info.plist`. Elle doit désigner
   le groupe coché, après résolution des variables de compilation.

Dans le projet fourni, cette valeur est `group.$(MESH_HOST_BUNDLE_ID)`.
Par exemple, si votre valeur commune `MESH_HOST_BUNDLE_ID` est
`ch.exemple.assistance`, le groupe attendu est `group.ch.exemple.assistance`.
Cet exemple est fictif : gardez votre propre identifiant. Le groupe de l’extension
est le **même que celui de l’app**, sans ajouter `.Broadcast`.

Si vous aviez déjà choisi un autre nom de groupe valide, gardez-le et faites
correspondre `MeshCentralAppGroup` dans les deux Info.plist à ce nom. Ne modifiez
pas le Bundle ID de l’app pour résoudre un problème de groupe.

Si Xcode affiche une erreur de profil, vérifiez dans le compte Apple Developer
que ce groupe est autorisé pour **les deux App IDs**, puis laissez la signature
automatique actualiser les profils. Apple décrit l’activation des groupes et
leur partage avec une extension dans sa
[documentation App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

Pour **Keychain Sharing**, vérifiez aussi le groupe commun aux deux cibles.
La valeur résolue de `MeshCentralKeychainGroup` dans les deux Info.plist doit
être autorisée par leur signature. Le projet fourni utilise
`$(AppIdentifierPrefix)$(MESH_HOST_BUNDLE_ID)`. Xcode préfixe les groupes du
trousseau ; évitez d’ajouter ce préfixe une seconde fois.
[Documentation Apple sur le trousseau partagé](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

Ces vérifications portent sur la **signature du build installé**. Modifier le
projet sur le Mac ne modifie pas le build déjà présent sur l’iPad : il faut
créer et installer un nouveau build pour appliquer une correction de groupe.

## Contrôler l’archive déjà envoyée sans reconstruire

Après avoir copié le correctif, ouvrez **Xcode → Window → Organizer → Archives**.
Sélectionnez l’archive qui correspond au build installé, puis utilisez
**Show in Finder** pour trouver son dossier `.xcarchive`.

Ouvrez Terminal à la racine du projet (le dossier contenant `Cargo.toml`).
Saisissez `python3 tools/check_sharing_configuration.py `, glissez le dossier
`.xcarchive` depuis Finder après l’espace, puis appuyez sur Entrée. Exemple
avec un chemin fictif à remplacer par celui de votre archive :

```sh
python3 tools/check_sharing_configuration.py "/chemin/vers/votre-archive.xcarchive"
```

Cet outil lit les Info.plist compilés et les droits de signature de l’app et
de l’extension avec l’outil Apple `codesign`. Il ne modifie aucun fichier,
n’envoie aucune donnée et n’affiche ni identifiants de groupe, ni liens
d’enrôlement, ni sortie brute de `codesign`.

- `APP_APP_GROUP_NOT_AUTHORIZED` ou `EXTENSION_APP_GROUP_NOT_AUTHORIZED` :
  le nom dans le Info.plist compilé ne figure pas dans les droits signés.
- `APP_GROUP_MISMATCH` : les deux Info.plist demandent des groupes différents.
- `...KEYCHAIN...` : vérifiez le trousseau commun et les droits de signature.
- `...INVALID` : une valeur manque ou une variable de compilation reste littérale.
- `OK` : la configuration de cette archive concorde ; ce n’est pas encore une
  preuve de fonctionnement ReplayKit sur l’iPad. Apple peut re-signer le build
  distribué par TestFlight, et l’accès au conteneur se teste sur l’appareil.

Ces codes peuvent être communiqués tels quels pour identifier le réglage à
corriger avant un nouvel envoi. Si `python3` manque sur le Mac, les vérifications
manuelles Xcode restent utilisables.

## Ce que change le correctif de code

- L’app vérifie son accès au conteneur partagé avec un petit fichier temporaire
  sans données personnelles, puis prépare le trousseau **avant** de fermer sa
  connexion. Le fichier de contrôle est supprimé après le test.
- Une préparation qui échoue laisse la connexion ordinaire ouverte, sauf
  interruption indépendante du réseau ou passage de l’app en arrière-plan.
- Les erreurs de conteneur ou de trousseau sont distinguées des erreurs WSS.
  Le refus de trousseau `-34018` signale de vérifier les droits de signature.
- Le bandeau affiche les étapes de diffusion : préparation, connexion,
  diffusion prête et partage actif. Il ne présente plus la connexion ordinaire
  fermée comme l’état global d’une diffusion active.

Ce contrôle vérifie les droits de **l’app qui l’exécute**. Il ne prouve pas
que l’extension possède le même profil : il faut toujours configurer les deux
cibles. Le contrôle ne crée ni entitlement, ni App Group, ni profil Apple.
Il n’introduit aucun contournement, stockage de repli ou transmission sans consentement.

## Appliquer uniquement les fichiers modifiés

Le ZIP `MeshCentral-iOS-0.3.0-sharing-preflight-fix.zip` contient :

```text
apple/App/Sources/AgentModel.swift
apple/App/Sources/MeshCentralIOSApp.swift
apple/Sources/MeshCentralAgent/AssistanceMailbox.swift
apple/Sources/MeshCentralAgent/BroadcastChannel.swift
apple/Tests/MeshCentralAgentTests/AssistanceTests.swift
tools/check_sharing_configuration.py
tools/test_sharing_configuration.py
docs/ipad-sharing-preflight.md
```

Décompressez-le dans un dossier temporaire, puis copiez uniquement ces fichiers
aux mêmes emplacements dans votre projet existant. Ne remplacez aucun dossier
entier. Aucun fichier à supprimer ou renommer. Les fichiers Swift sont déjà
référencés dans le projet ; il n’y a rien à ajouter dans Xcode.

Le ZIP ne contient aucun `.xcodeproj`, Info.plist, entitlement, certificat,
profil ou secret. Vos Team, Bundle IDs, groupes et préférences sont conservés.
Les ajustements de signature nécessaires se font dans Xcode selon les étapes
précédentes. Ne relancez pas le générateur de projet.

Dans Xcode, augmentez le **Build** pour l’app et l’extension, en gardant la même
valeur pour les deux. Faites **Product → Clean Build Folder**, puis
**Product → Archive** pour **Any iOS Device (arm64)**. Envoyez la nouvelle
archive en test interne et mettez à jour l’app depuis TestFlight sur l’iPad.

## Reprendre le test sur l’iPad

1. Ouvrez l’app, connectez-la, puis touchez **Préparer le partage de l’écran**.
2. Si une erreur précise d’App Group ou de trousseau apparaît, relevez son texte.
   La connexion doit rester ouverte tant que l’app reste au premier plan.
3. Si la préparation réussit, le bandeau indique **Partage préparé**.
   Touchez le bouton système rond puis **Lancer la diffusion**, sans quitter
   l’app pendant le démarrage et l’autorisation du technicien.
4. Attendez **Diffusion prête**, ouvrez le visualiseur MeshCentral puis
   acceptez **Autoriser cette assistance** sur l’iPad.
5. Ouvrez Réglages et vérifiez que l’image continue de se mettre à jour.
   Testez ensuite l’arrêt de la diffusion depuis l’iPad.

## Vérifications et limites

Les sources, les références Xcode, les licences et le contenu incrémental
ont été contrôlés sous Windows. Les neuf cas Python de comparaison des
configurations signées ont été exécutés sur des données fictives ; la lecture
d’une vraie archive par `codesign` reste à exécuter sur le Mac.
Les nouveaux cas XCTest couvrent les groupes
absents/non résolus, les conteneurs indisponibles et le nettoyage du fichier de
contrôle sans suppression des autres fichiers. Ils sont fournis dans la cible
de tests existante mais **n’ont pas été exécutés ici**, faute de Xcode/SDK Apple.
Ils peuvent être lancés avec `⌘U` sur le Mac, avec une Team pour la cible de tests.
La compilation Swift, la signature et le parcours ReplayKit sur iPad restent
à vérifier. Aucun changement Rust, aucune dépendance ajoutée ; code et guide
originaux sous Apache-2.0.

Le checkout serveur reste à `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Le HEAD officiel observé est `412e2aeb3f209df1c1a238de974d3a44185d7006` ; fetch et
création de branche restent bloqués par les droits d’écriture de `.git`.
Aucune intégration serveur n’a été réalisée dans ce correctif iOS.
