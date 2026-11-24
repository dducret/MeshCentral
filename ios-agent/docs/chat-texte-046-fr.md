<!-- SPDX-License-Identifier: Apache-2.0 -->
# Messages du chat en grands caractères sur iPhone et iPad — 0.4.6

Les conversations MeshMessenger affichent les messages reçus et envoyés dans
des bulles agrandies. La taille de base est de 24, puis elle suit le réglage de
texte d’iOS avec Dynamic Type. Les messages déjà affichés se redimensionnent
au prochain contrôle de la page si le chat est toujours ouvert. Les sauts de
ligne sont conservés et les longues chaînes reviennent à la ligne. Un changement
de taille garde la fin de la conversation visible si l’utilisateur la suivait.
Il ne force pas de retour en bas quand l’utilisateur lit plus haut.

Sur iPhone et dans les vues étroites, les commandes audio utilisent une partie
de l’espace restant et peuvent défiler séparément. Le lecteur de messages garde
sa place dans la conversation. En faible hauteur, notamment sur iPhone en
paysage, la rédaction revient à une rangée plus compacte. Le bouton **Terminer**
reste en haut. Le chat natif de la vue Assistance utilise aussi un style de texte
plus grand qui suit le réglage système.

## Installer le complément

1. Partez du projet 0.4.5 ayant reçu le complément
   `MeshCentral-iOS-0.4.5-assistance-visible-update.zip`. Fusionnez le contenu
   de `MeshCentral-iOS-0.4.6-texte-chat-update.zip` à la racine contenant
   `Cargo.toml` et `apple/`. La liste et les empreintes sont dans
   `release-0.4.6.json` et `SHA256SUMS-0.4.6.json`. Aucun fichier à supprimer ou
   renommer.
2. Dans Xcode, mettez **Version à 0.4.6** sur la cible app et l’extension, en
   Debug et Release, puis choisissez le même nouveau **Build**. Gardez Team,
   Bundle IDs, App Groups, trousseau et signature. Gardez aussi
   `MeshCore.xcframework` 0.4.2. Le projet Xcode configuré n’est pas inclus dans
   le ZIP et ne doit pas être régénéré.
3. Compilez un Build Release et testez sur **iPhone et iPad**. La cible conserve
   iOS 16 comme minimum et déclare les deux familles d’appareils.

## Valider la lisibilité

1. Acceptez un chat sur chaque appareil. Demandez au technicien d’envoyer un texte
   court, un message sur plusieurs lignes, une chaîne longue et des emoji.
   Répondez depuis l’app. Vérifiez le retour à la ligne sans défilement horizontal.
2. Essayez la taille normale et la taille d’accessibilité maximale via
   **Réglages → Accessibilité → Affichage et taille du texte → Texte plus grand**.
   Après un passage dans Réglages, ouvrez une nouvelle invitation. Si vous changez
   la taille depuis le Centre de contrôle et que le chat reste ouvert, vérifiez
   aussi le redimensionnement des bulles déjà affichées.
3. Vérifiez la lecture des anciens messages quand la taille change, puis le
   suivi des derniers messages quand vous êtes en bas. Essayez portrait,
   paysage, vue partagée et clavier ouvert. Testez **Terminer** et VoiceOver.
4. Vérifiez l’émission et la réception de texte et la voix dans les deux sens.
   Dans MeshCentral et les diagnostics, vérifiez la version native **0.4.6**.

## Vérification et périmètre

SwiftUI calcule la taille avec `@ScaledMetric` relatif au corps du texte. La
WebView consentie reçoit uniquement une valeur numérique bornée à 16–96 CSS px
dans son contrôle de page existant. Une règle CSS s’applique à l’historique de
texte local et reçu. Le test en machine virtuelle JavaScript contrôle le message
reçu côté MeshMessenger, les limites, les mises à jour de taille, le défilement
et les états existants du chat et du micro. Les tests utilisent le template
local et le template officiel 1.3.1. Ils ne rendent pas le CSS sur un appareil.

Les contrôles Windows Messenger, inventaire, licences et structure Xcode passent.
La fusion du ZIP et les empreintes ont été vérifiées. Compilation Xcode, rendu
iPhone/iPad, VoiceOver et test physique restent ouverts. La version native et
ses métadonnées passent à 0.4.6. Rust et ABI restent à 0.4.2. Aucun changement
serveur, plugin ou dépendance n’est requis.

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. La branche par
défaut distante `master` pointait sur `1eab6b80c90f9e9911f178aa518bf2192e47602c`.
Les métadonnées Git sont en lecture seule dans cet environnement.

[Dynamic Type et ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric) · [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
