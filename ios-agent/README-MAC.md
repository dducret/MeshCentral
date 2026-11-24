<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Latest source candidate: ReplayKit with SDK 26, version 0.5.2. -->

Pour la **0.5.2**, appliquez le [correctif d’annonce du partage
ReplayKit](docs/diffusion-replaykit-052-fr.md) après le retour au SDK 26.

Pour compiler la **0.5.1 avec Xcode 26**, appliquez le [correctif de retour au
SDK 26](docs/retour-sdk26-051-fr.md) si vous avez intégré les sources
ScreenCaptureKit. Si votre projet est encore en 0.5.0, compilez-le directement
avec Xcode 26. Les deux parcours utilisent ReplayKit.

Pour la **0.5.0**, appliquez la [mise à jour incrémentale depuis la
0.4.8](docs/seance-050-fr.md). Le guide couvre le nouveau contrôle **Masquer mon
écran**, le framework Rust 0.4.5 et la recette Release sur iPhone et iPad.

Pour la **0.4.8**, suivez le [guide d’installation et de recette de la reprise
audio](docs/reprise-audio-048-fr.md). Il indique comment appliquer le complément
à votre projet Xcode 0.4.7 et reconstruire le framework Rust.

Le complément [MeshMessenger 0.4.1](docs/messenger-041-update-fr.md) s’installe
après la 0.4.0. Il ajoute une invitation Chat et l’audio au premier plan, avec une
clé microphone à ajouter uniquement dans l’app. Suivez cette procédure sans
régénérer votre projet Xcode ; les étapes plus anciennes ci-dessous restent historiques.

# MeshCentral pour iPad et iPhone — candidat 0.4.0

Pour la 0.4.0, suivez [l’installation incrémentale et la recette
Mac/iPad 0.4.0](docs/ipad-040-update-fr.md). Elle part du complément console 0.3.0,
préserve votre projet Xcode et demande uniquement les réglages Version/Build
précisés. Ne régénérez pas le projet. La compilation Apple et la recette physique
0.4.0 restent à effectuer ; [les vérifications Windows](docs/ipad-040.md) sont distinctes.

Les sections ci-dessous conservent les indications d’installation initiale de la
base 0.3 et son historique. Les nouveaux libellés et essais 0.4 sont dans le guide
ci-dessus ; le succès physique du build précédent ne les valide pas encore.

**Complément précédent 0.3.0 :** le plugin Assistance iOS, les procédures
réutilisables, le compte rendu et le diagnostic enrichi s’installent avec
[cette notice](docs/assistance-console-update-fr.md), après la mise à jour
[guidage et démarrage rapide](docs/guided-assistance-update-fr.md).
Votre projet Xcode configuré est conservé ; ne le régénérez pas.

Ce ZIP contient un **projet Xcode, les sources Swift et le cœur Rust**. Il permet
de préparer une application de test pour iPhone/iPad sous iOS 16 ou ultérieur.
Il ne contient pas d’application déjà signée, de SDK Apple, de framework tiers
ou de serveur MeshCentral. La visualisation reste en lecture seule :
la fenêtre de l’app dans le simulateur, et une extension ReplayKit pour l’écran
complet d’un iPhone réel. Aucune saisie ou commande distante n’est exécutée.

La version **0.3** ajoute le chat, la qualité adaptative, les annotations sur
capture, les documents dans les deux sens (2 Mio maximum) et un diagnostic
exportable. Ces fonctions utilisent une session d’assistance autorisée.

**Validation historique 0.3.0 :** 37 tests Rust, 11 scénarios WSS/crypto antérieurs et contrôles
du consentement et de la qualité via l’ABI, tests du panneau et du visualiseur
MeshCentral, structure du projet et ZIP. Vous avez confirmé le fonctionnement
du partage d’écran dans le simulateur, puis la compilation de la version 0.3
après les corrections Swift et d’identifiant de l’extension. Vous avez ensuite
confirmé le partage d’écran sur un iPad physique. **Le nouveau guidage et le
démarrage rapide, ainsi que le nouveau diagnostic, n’ont pas encore été compilés
ou testés sur iPad ici.** Le plugin et le panneau ont des tests Node locaux ;
leur rendu et leur connexion au serveur déployé restent à vérifier.

## Installer sur un iPad éloigné du Mac

Avec votre abonnement Apple Developer actif, suivez le
[guide TestFlight pas à pas](docs/testflight-ipad.md). L’iPad n’a pas besoin
d’être branché au Mac ni sur son réseau. Utilisez votre projet déjà configuré
et le complément incrémental d’icône ; conservez Team, identifiants et groupes.
L’envoi à App Store Connect nécessite actuellement **Xcode 26 ou ultérieur**,
selon les [exigences Apple](https://developer.apple.com/news/upcoming-requirements/?id=04282026a).

## Nouveau : installer le panneau technicien

Pour utiliser les fonctions, installez les **quatre fichiers du dossier
operator** sur votre serveur, selon le [guide du panneau](operator/README.md).
Ce sont des fichiers web Apache-2.0 ; aucun changement de code serveur n’est
nécessaire. Une fois installée, ouvrez la page HTTPS `/ios-assist.html` sur votre
serveur après vous être connecté à MeshCentral dans le même navigateur.
L’onglet Desktop habituel fonctionne encore, mais ses boutons Chat/Files
ne pilotent pas les nouveaux échanges.
Le [plugin fourni](plugin/iosAssistance/README.md) ouvre cette console depuis
**la fiche de l’appareil → Plugins → Assistance iOS**, avec l’iPad présélectionné.

## Test immédiat avec TeamViewer et le simulateur

1. Pour une première installation, décompressez le ZIP complet dans un dossier
   dédié. Pour une mise à jour, appliquez seulement les fichiers du complément
   incrémental à votre dossier existant, suivant son guide ; conservez le projet
   Xcode configuré et ne relancez pas le générateur de projet.
2. Dans le **projet bleu → PROJECT MeshCentralIOS → Build Settings → All**, cherchez
   **MESH_HOST_BUNDLE_ID**. Mettez votre ancien Bundle Identifier dans cette valeur
   commune. Conservez aussi votre ancienne Team si elle était configurée. Le
   projet en déduit les identifiants de l’app et de l’extension ; ne les modifiez
   pas séparément dans les cibles. Cela permet de retrouver l’enrôlement et la clé.
3. Sélectionnez le schéma **MeshCentralIOS**, votre simulateur existant, puis `⌘R`.
   Reconnectez l’app ; réimportez l’invitation si aucune configuration n’est présente.
4. Dans le nouveau panneau **ios-assist.html**, sélectionnez l’iPhone et cliquez
   **Demander une session**. Fermez une éventuelle connexion Desktop existante.
5. Dans le simulateur, vérifiez le nom du technicien et l’éventuel enregistrement,
   puis touchez **Autoriser cette assistance**. La vue de l’application doit
   apparaître dans le visualiseur. Faites défiler la page pour vérifier le mouvement.
6. Touchez **Arrêter le partage**. L’image doit cesser d’être transmise et le
   visualiseur se déconnecter. Une nouvelle session exige un nouvel accord.

Pour essayer les nouveautés pendant la session, ouvrez **Chat, documents,
captures et diagnostic** dans l’app. Suivez les cinq essais du
[guide technicien](operator/README.md). Le bouton **Arrêter** reste accessible
dans la barre supérieure de cet écran.

Le simulateur capture seulement la fenêtre de l’agent : il ne capture ni l’écran
d’accueil, ni les autres applications, ni le bureau du Mac. Le code utilise le
rendu public UIKit et ne nécessite pas de capture ReplayKit dans le simulateur.
La qualité varie de 1 à 3 images JPEG par seconde, selon le réseau ; la capture
de la fenêtre du simulateur peut rester plus petite que la résolution maximale.
La session dure au maximum dix minutes. Le clavier et la souris du visualiseur sont
ignorés. Le message système CoreHaptics observé dans la version 0.1 ne concerne
pas ce flux d’images.

## Écran complet sur iPhone — essai ultérieur

L’extension **MeshCentralBroadcast** est intégrée au projet. Configurez la même
Team pour l’app et l’extension ; le groupe de trousseau commun est généré depuis
`MESH_HOST_BUNDLE_ID` et le préfixe de signature Apple.
**Nouveau en 0.3 :** activez aussi **Signing & Capabilities → App Groups** dans
**les deux cibles** et sélectionnez le même groupe
`group.<votre MESH_HOST_BUNDLE_ID>`, par exemple
`group.ch.votreorganisation.meshcentralios`. Ce groupe transporte les documents
et captures entre l’app et ReplayKit. Il doit être enregistré et autorisé dans
les profils de signature pour un iPhone réel, conformément au
[guide Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).
Le groupe du trousseau doit aussi être autorisé. Le simulateur utilise le chemin
direct en mémoire pour ces fonctions ; il ne valide pas cette configuration.

Sur l’iPhone, après l’enrôlement, touchez **Préparer le partage de l’écran**, puis
le bouton de diffusion système et **Lancer la diffusion**. Le démarrage transfère
la connexion à l’extension, avec la même identité de l’appareil. Restez dans
l’application pendant que le technicien ouvre le panneau et se connecte ; acceptez
sa demande avec **Autoriser cette assistance**. Vous pouvez ensuite changer
d’application. Le partage est soumis aux restrictions de capture d’iOS ; les
contenus protégés peuvent ne pas apparaître. Le microphone et l’audio ne sont
jamais transmis.

Arrêtez avec le contrôle de diffusion iOS ou **Arrêter la diffusion** dans l’app.
Le bouton de l’app transmet l’arrêt à l’extension, contrôlé toutes les 0,5 seconde.
Une pause de capture, une perte de connexion ou la limite de dix minutes termine
la diffusion et impose un nouveau démarrage/consentement. Les décisions sont
liées à une seule diffusion et un seul technicien. Les images du flux restent en
mémoire ; les captures/documents explicitement échangés utilisent temporairement
le conteneur App Group protégé, puis sont nettoyés à la fin de la session.
Revenez dans l’app pour le chat, les annotations et les documents.

L’app doit rester ouverte pour **accepter** une nouvelle demande. Une diffusion
démarrée ne donne pas automatiquement accès à l’écran au technicien. Ce parcours
ReplayKit complet reste à vérifier sur appareil réel.

## 1. Préparer le Mac

- Installez Xcode complet, avec un SDK compatible avec la version iOS de votre
  appareil. Le projet utilise Swift 5 et requiert un compilateur Swift 5.9 ou
  ultérieur ; Xcode 16 ou ultérieur est conseillé. Ouvrez Xcode une fois pour
  terminer son installation. Dans ses réglages, sélectionnez Xcode dans
  **Locations → Command Line Tools**.
- Installez Rust via [rustup](https://rust-lang.org/tools/install/).
  Ce projet requiert **Rust 1.99 ou ultérieur** ; la version vérifiée ici est
  1.99.1. Si nécessaire, lancez `rustup update stable`.
- Décompressez tout le ZIP dans un dossier local. Gardez l’arborescence : le
  projet Xcode utilise les sources Rust situées deux dossiers plus haut.

Dans Terminal, placez-vous dans le dossier décompressé `MeshCentral-iOS`, puis :

```sh
sh apple/App/Scripts/prepare-mac.sh
open apple/App/MeshCentralIOS.xcodeproj
```

Le script installe les cibles Rust iPhone, simulateur Apple Silicon et simulateur
Intel, exécute les tests Rust et demande à Xcode de lire le projet. Une connexion
Internet est nécessaire pour installer ces cibles. Les compilations suivantes
utilisent Cargo avec `--offline --locked` : aucune dépendance externe n’est
téléchargée pendant le build Xcode. Aucun XcodeGen, CocoaPods ou paquet Swift
externe n’est nécessaire.

## 2. Compiler et lancer sur l’iPhone

1. Dans Xcode, sélectionnez le projet bleu **MeshCentralIOS**, puis la cible
   **MeshCentralIOS → Signing & Capabilities**. Activez la signature automatique,
   choisissez votre **Team** pour **MeshCentralIOS** et **MeshCentralBroadcast**.
   Réglez l’identifiant unique dans **PROJECT → Build Settings → MESH_HOST_BUNDLE_ID**,
   par exemple `ch.votreorganisation.meshcentralios`. Les deux cibles l’héritent.
   Votre compte Apple doit être configuré dans Xcode.
2. Branchez l’iPhone, confirmez la confiance demandée par macOS/iOS et activez
   le **Mode développeur** si Xcode le demande. Après le jumelage, ce réglage
   se trouve dans **Réglages → Confidentialité et sécurité → Mode développeur**.
   Voir les [instructions Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
3. Sélectionnez le schéma **MeshCentralIOS** et votre iPhone comme destination,
   puis cliquez sur **Run** (`⌘R`). La première compilation construit aussi la
   bibliothèque Rust. [Exécution depuis Xcode](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

Pour un premier contrôle sans signature, sélectionnez un simulateur iPhone.
Le simulateur ne remplace pas les tests du trousseau et de la connexion sur
l’appareil réel. Les cibles Rust sont documentées dans le
[guide officiel Rust pour iOS](https://doc.rust-lang.org/rustc/platform-support/apple-ios.html).

## 3. Enrôler et connecter

Dans l’application :

1. Donnez un nom à l’appareil et **collez votre lien HTTPS d’invitation
   MeshCentral** (`https://serveur/agentinvite?c=…`). Les invitations sans date
   d’expiration et celles à durée limitée utilisent le même parcours ; leur
   validité est décidée par le serveur. Le lien fourni pour les tests n’est
   pas inclus dans ce ZIP : copiez le dernier lien de la conversation.
2. Touchez **Lire l’invitation**. L’app charge la page en HTTPS, extrait son
   lien mobile `mc://` et affiche l’adresse WSS et l’empreinte du serveur.
   Vérifiez le serveur attendu, puis touchez **Enregistrer l’enrôlement**.
3. Touchez **Se connecter**. L’état doit devenir **Connecté à MeshCentral**
   après l’authentification mutuelle et l’accusé de réception du serveur.
   Dans MeshCentral, recherchez le nom choisi dans le groupe de l’invitation.
   Si votre serveur impose une approbation ou un quota, vérifiez aussi cette
   politique d’ajout d’appareils.

Les autres formats acceptés sont le lien mobile `mc://`, un fichier `.msh`
exporté par MeshCentral ou la saisie manuelle de `MeshServer`, `ServerID` et
`MeshID`. Le **ServerID est l’empreinte de la clé de l’agent serveur**, pas
l’empreinte du certificat TLS du site. Il doit provenir d’une source de confiance.

La page d’invitation n’est ni affichée dans une WebView ni exécutée comme du
JavaScript. Seul le littéral `magenturl` produit par MeshCentral est lu. Les
redirections HTTPS sont refusées : utilisez l’URL définitive. Un thème serveur
qui retire ce champ nécessitera un lien `mc://` ou un fichier `.msh` à la place.
L’app ne conserve pas le jeton de l’invitation ; les paramètres validés et la
clé privée restent dans le trousseau, accessibles sur cet appareil déverrouillé.

Pour un serveur avec une autorité TLS privée, importez son **certificat public
d’autorité** `.crt`, `.cer` DER ou PEM dans la section correspondante **avant**
la lecture de l’invitation. La même autorité sera utilisée pour WSS. Le nom DNS,
les dates et la chaîne restent vérifiés ; aucun mode « ignorer les certificats »
n’est prévu. Pour un certificat public, configurez sa chaîne complète sur le
serveur. Le résultat de la validation Windows ne garantit pas celui d’iOS.

## Vérifier le comportement

- Déconnectez puis reconnectez : le même appareil doit retrouver son identité.
- Quittez l’application dans le simulateur : la connexion et le partage s’arrêtent.
  Sur iPhone, seule la diffusion ReplayKit explicitement démarrée continue hors
  de l’app ; la connexion ordinaire s’arrête comme auparavant.
- Une invitation invalide/expirée, un mauvais ServerID ou un certificat non
  reconnu doivent produire une erreur, jamais une connexion non vérifiée.
- Le bouton **Changer d’enrôlement** retire la configuration du trousseau et
  ferme la connexion. Il conserve la clé et ne supprime pas le nœud sur le serveur.
  Pour changer de groupe sur le même serveur, déplacez le nœud dans MeshCentral :
  un nœud déjà connu conserve le groupe décidé par le serveur.
- `⌘U` exécute les tests XCTest du parsing, du trousseau et des signatures.
  Pour les tests sur iPhone, configurez aussi la Team de la cible
  **MeshCentralIOSTests**. Ne confondez pas ces tests avec une validation complète
  du transport réseau Apple, qui reste à effectuer contre votre serveur.

L’identifiant d’architecture `0xfffffff0` est **expérimental et non attribué**.
MeshCentral peut afficher un type inconnu avec une icône générique. L’agent
annonce Desktop dans le simulateur ou lorsque l’extension possède la connexion.
Pas de terminal, scripts, accès arbitraire aux fichiers ou saisie distante.
Seuls les documents explicitement sélectionnés/acceptés sont échangés.
La connexion ne vaut pas
consentement à partager l’écran.

## Dépannage

- **Rust introuvable / cible manquante :** relancez `prepare-mac.sh` ; Xcode
  ajoute automatiquement `~/.cargo/bin` au PATH de sa phase de compilation.
- **SDK introuvable :** vérifiez que Command Line Tools pointe sur Xcode complet.
- **Signing requires a development team :** choisissez une Team pour la cible
  concernée et un Bundle Identifier disponible.
- **Certificat refusé :** vérifiez la chaîne complète, le nom DNS et l’heure
  de l’iPhone ; importez seulement une autorité privée obtenue de confiance.
- **Serveur local inaccessible :** accordez l’accès réseau local demandé par
  iOS et utilisez un nom joignable depuis le téléphone. `localhost` désigne
  l’iPhone lui-même, pas votre Mac.
- **Connexion refusée après authentification :** vérifiez les journaux du serveur,
  les règles d’enrôlement, le groupe et les restrictions d’architecture. Ne
  publiez pas le lien d’invitation ou des clés dans un rapport de diagnostic.

## Sources, licences et vérifications

Toutes les sources originales sont sous **Apache-2.0**, avec le texte complet
et les notices dans `LICENSE`. Aucun paquet Cargo/Swift tiers n’a été ajouté.
Les SDK Apple sont utilisés selon votre autorisation ; ils ne sont pas inclus.
L’inventaire [licences](docs/licensing.md) distingue sources, SDK, outils et
futurs binaires. Le ZIP source ne distribue pas les dépendances du serveur
MeshCentral, dont certaines restent hors de l’allowlist Apache-2.0/MIT.

Le protocole a été étudié sur MeshCentral
`67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Voir [la connexion sécurisée](docs/secure-connection.md)
et [le projet Xcode](docs/xcode-app.md). `SHA256SUMS.json` donne les empreintes des
fichiers livrés. `release-info.json` rappelle la portée des validations.

Les contrôles Rust autonomes sont :

```sh
cargo fmt --all --check
cargo clippy --offline --locked --workspace --all-targets -- -D warnings
cargo test --offline --locked --workspace
# Facultatif, avec Node.js installé :
node tools/check-licenses.cjs
```

Les outils `check-upstream.cjs` et `check-native.ps1` sont conservés comme sources
de développement ; ils requièrent le dépôt MeshCentral complet (et, pour le
second, Windows/.NET). Ils ne sont pas nécessaires pour construire l’app iOS.
