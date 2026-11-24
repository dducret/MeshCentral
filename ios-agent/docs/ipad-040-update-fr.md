<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installer et valider l’assistance iPad 0.4.0

Cette livraison contient les **sources candidates à la validation** de la 0.4.0.
Les contrôles Windows ne remplacent pas une compilation Xcode ou un essai iPad.
Les nouvelles fonctions ne sont pas encore déclarées validées sur appareil.

## Base indispensable

Appliquez ce complément après `MeshCentral-iOS-0.3.0-assistance-console-update.zip`
(SHA-256 `decc71f6c8352e29c4e0f3102a4f5c6a2e316eb2bc5837b767beae61328e7a8b`).
Cette base exige elle-même le complément guidage et les correctifs précédents.
La livraison d’une archive ne signifie pas qu’elle a été installée sur votre Mac
ou serveur. Vérifiez cette base avant la fusion.

Le ZIP 0.4.0 contient seulement les sources/documentations modifiées ou nouvelles,
`release-0.4.0.json` (base, liste des fichiers et modifications manuelles) et
`SHA256SUMS-0.4.0.json`. Aucun fichier à supprimer ou renommer. Aucun projet
Xcode complet, Info.plist, entitlement, profil ou réglage de signature n’est inclus.

## 1. Préserver puis mettre à jour le projet Mac

1. Arrêtez toute diffusion iPadOS, fermez Xcode et sauvegardez votre projet
   actuellement configuré. Conservez aussi le build précédent pour revenir en
   arrière si la recette révèle un problème.
2. Décompressez `MeshCentral-iOS-0.4.0-ipad-assistance-update.zip` dans un dossier
   temporaire. Entrez dans son dossier `MeshCentral-iOS-0.4.0-ipad-assistance-update`.
3. Vérifiez les fichiers extraits avec Python 3, depuis ce dossier :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   checks = json.loads(pathlib.Path('SHA256SUMS-0.4.0.json').read_text())
   for name, expected in checks.items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, name
   print('Empreintes des fichiers conformes')
   PY
   ```

4. Fusionnez avec le dossier de votre projet contenant `Cargo.toml` :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Adaptez le chemin. N’ajoutez pas `--delete` et ne remplacez pas tout le dossier
   dans Finder. Si vous avez modifié des sources depuis la base, comparez et
   fusionnez ces fichiers avant de les copier.
5. Rouvrez **votre** `apple/App/MeshCentralIOS.xcodeproj`. Dans **Build Settings**,
   pour les cibles **MeshCentralIOS** et **MeshCentralBroadcast**, mettez uniquement
   **Version / Marketing Version (`MARKETING_VERSION`) à `0.4.0`**, en Debug et
   Release. Augmentez leur **Build (`CURRENT_PROJECT_VERSION`) à une même valeur
   supérieure à vos builds déjà envoyés**. Ne remplacez pas le `.pbxproj`.
6. Conservez Team, Bundle IDs, App Groups, groupes Keychain, profils et réglages
   locaux. Aucun nouveau fichier Swift à ajouter : les nouvelles déclarations
   restent dans les fichiers déjà référencés. **Ne lancez pas `generate_xcode.py`.**
7. Faites **Product → Clean Build Folder**, puis **Product → Test** sur simulateur.
   Compilez aussi les deux cibles pour appareil réel et pour l’archive Release.
   App et extension doivent provenir de la même 0.4.0 : leur IPC a évolué.
8. Vérifiez la configuration réellement signée avec
   [le contrôle App Groups/Keychain existant](ipad-sharing-preflight.md), puis
   installez le candidat sur l’iPad selon votre procédure habituelle. Un envoi
   TestFlight reste une opération à effectuer sur votre compte, pas une action
   réalisée par cette livraison.

Notez le modèle d’iPad, iPadOS, Xcode, le SDK, Version/Build des deux cibles,
la version/révision MeshCentral et le navigateur utilisés. Contrôlez dans le SDK
du Mac les annotations ReplayKit et les exigences de distribution Apple en vigueur.
Un simulateur ne valide pas la signature App Group ni le cycle de diffusion réel.

## 2. Mettre à jour le panneau technicien

Remplacez ensemble les quatre fichiers `operator/ios-assist.html`,
`ios-assist.css`, `ios-assist.js` et `ios-console.js` dans le dossier public
personnalisé existant du serveur. Rechargez complètement la page ; les URL de
ressources portent maintenant `?v=ipad040`. Utilisez la même origine HTTPS et la
session MeshCentral habituelle. Conservez les autres fichiers/configurations.

Le plugin **iosAssistance 0.1.0 reste inchangé**. S’il est déjà installé, aucune
modification de sa configuration n’est nécessaire. S’il manque, suivez
[sa notice](../plugin/iosAssistance/README.md) en préservant les autres plugins.
Le protocole `iosAssist` reste v1. Une app 0.3.0 reste utilisable avec la console,
mais n’annonce pas le nouveau temps restant. Aucune modification des handlers,
de la base de données ou des permissions MeshCentral n’est fournie.

## 3. Recette P0 obligatoire sur iPad

Utilisez des documents et images de test sans données personnelles. Fermez les
autres visualiseurs : un seul technicien à la fois. Pour chaque scénario, notez
PASS/FAIL, Build, durée, symptôme et éventuel diagnostic expurgé.

| Essai | Résultat exigé |
| --- | --- |
| Démarrage rapide | Choisir « Préparer et autoriser l’assistance », lancer la diffusion dans iPadOS, puis demander une session dans Plugins → Assistance iOS. Première image uniquement après les deux accords. |
| Validation séparée | Préparer sans accord anticipé. Le nom du technicien apparaît ; aucun écran transmis avant acceptation. Refuser doit terminer la demande. |
| Préparation expirée | Attendre 120 s sans lancer. L’ancien démarrage ne doit pas autoriser une assistance. Préparer à nouveau exige un nouveau choix local. |
| Arrêt local et arrêt iPadOS | Tester les deux. La diffusion et les échanges cessent ; les contrôles de l’ancienne session ne redeviennent pas utilisables. |
| Limite de dix minutes | Le compte à rebours porte sur la diffusion, y compris attente/connexion. Elle se termine à la limite ; aucune prolongation silencieuse. |
| Wi-Fi coupé puis rétabli | La console signale perte de connexion ou mesures/images anciennes. Aucune reprise du partage ni réutilisation de l’ancien accord. |
| Verrouillage et interruption système | Arrêt ou révocation conforme au cycle iPadOS ; au retour, aucun faux état « partagé ». Une nouvelle session exige une préparation. |
| Arrêt non confirmé | L’app garde l’état d’arrêt et n’autorise pas de relance automatique. Utiliser le contrôle iPadOS. Après 10 s, confirmer « J’ai arrêté… » uniquement après l’arrêt effectif. |
| App fermée puis rouverte | Une diffusion encore active est identifiée ; une diffusion muette est révoquée ; une session déjà terminée ne bloque pas une nouvelle préparation. |
| Import tardif | Ouvrir le sélecteur ou choisir un document, puis interrompre/recommencer l’assistance avant la fin de la sélection ou de la lecture. L’ancien document ne doit jamais partir dans la nouvelle session. |
| Nettoyage tardif | Arrêter puis relancer plusieurs fois. Aucun ancien message, fichier, illustration ou état d’autorisation ne doit apparaître dans la nouvelle session. |

Exécutez **cinq sessions successives**, dont une atteignant dix minutes, avec des
changements d’application, rotations et un aller-retour réseau. Tout défaut de
consentement, d’arrêt, d’isolation entre sessions ou plantage reproductible du
parcours principal bloque la validation du candidat.

## 4. Recette P1 et serveur

- **Guidage :** charger un modèle, envoyer une étape, demander de l’aide, répondre
  dans le chat, confirmer puis avancer. Une ancienne réponse ne doit pas terminer
  une nouvelle étape. Arrêter le guide conserve la possibilité d’arrêter la session.
- **Captures :** demander une image pendant l’affichage de Réglages, revenir dans
  l’app, examiner l’aperçu puis accepter ou refuser. Vérifier le zoom, le défilement
  et l’alignement des traits ; une illustration d’étape reste figée si une nouvelle
  capture générale arrive. L’arrêt doit aussi rester accessible dans le zoom.
- **Documents :** essayer dans les deux sens 1 octet, 9 Kio et 2 Mio ; refuser un
  document, annuler à mi-transfert et attendre un délai dépassé. Un fichier supérieur
  à 2 Mio est refusé. La progression d’envoi compte les octets confirmés ; « reçu »
  exige le transfert complet et l’intégrité. Effacer les échanges annule les transferts.
- **Retour dans l’app :** recevoir un message, une étape et une demande de capture
  pendant que Réglages est affiché. Les nouveautés sont signalées au retour dans
  notre app, sans notification push ni surimpression dans Réglages.
- **Disposition/accessibilité :** portrait, paysage, fenêtre étroite, clavier
  affiché, plus grandes tailles de texte et VoiceOver. Aucune action essentielle
  inaccessible ; ordre de lecture cohérent et état compréhensible sans la couleur.
- **Console réelle :** page indépendante et plugin, rafraîchissement de la même
  fiche, changement d’appareil, fermeture de page et session navigateur expirée.
  Vérifier que les images anciennes sont signalées et que la fermeture efface
  l’écran. Tester compte sans Chat / Notify et compte avec No files.
- **Compatibilité :** console 0.4 avec agent 0.3, console précédente avec agent
  0.4, Bureau MeshCentral standard avec agent 0.4. Les fonctions non annoncées
  restent indisponibles. Le temps restant d’un agent ancien est indiqué inconnu.
- **Exports :** diagnostic sans secret/contenu ; compte rendu sans messages,
  instructions ou notes par défaut, inclusion seulement sur choix explicite.

## 5. Mesures et décision de validation

Ces seuils sont des **critères à mesurer**, pas des performances déjà constatées.
Pour le réseau nominal : iPad déverrouillé, bon Wi-Fi, relais joignable, aucune
restriction volontaire de débit. Mesurez après acceptation des accords requis.

| Mesure | Critère du candidat |
| --- | --- |
| Première image sur réseau nominal | ≤ 10 s après accord local et demande du technicien ; sinon relever le délai et corriger avant validation nominale. |
| Arrêt local sur réseau nominal | Diffusion et relais fermés en ≤ 2 s après le bouton ; aucune nouvelle capture autorisée après traitement de l’arrêt. Des octets déjà en vol ne peuvent pas être rappelés. |
| Images/télémétrie anciennes | Avertissement après 10 s d’absence, à la prochaine actualisation de la page active (environ 1 s) ; l’horloge du navigateur peut ralentir en onglet masqué. |
| Réseau lent | Pas d’accumulation illimitée ; baisse de qualité ou interruption explicite. Aucune fausse confirmation de réception et aucun contournement TLS. |
| Mémoire/thermique | Relever pic et évolution dans les outils Xcode pendant les cinq sessions et la session longue. Aucun arrêt par pression mémoire, aucune croissance continue après nettoyage. Documenter les valeurs observées ; ne pas inventer de budget mémoire ReplayKit universel. |
| Reprise | Zéro reprise sans nouveau consentement, sur tous les essais d’arrêt/coupure. |

Un résultat manquant reste **non vérifié**. Conservez le candidat en test tant que
les P0 ne passent pas. Une limitation propre à un modèle/iPadOS ou navigateur doit
être corrigée ou explicitement restreindre le périmètre validé. Une archive signée
ou une publication nécessite aussi les contrôles de licences des artefacts liés
et les conditions Apple correspondantes ; ce ZIP ne livre que des sources.

## Contrôles Windows et retour arrière

Le [bilan technique](ipad-040.md) consigne les commandes réellement exécutées.
Il distingue tests Rust/ABI/Node et contrôles de structure des XCTest, du rendu
navigateur, de la signature et des essais physiques restant à réaliser.

En cas d’échec, arrêtez la diffusion, restaurez **votre sauvegarde du projet**
et les quatre anciens fichiers opérateur. Recompilez ensemble l’app et l’extension
avec un numéro Build adapté à votre canal de test. Préservez les identifiants et
groupes de signature. Ne mélangez pas une app 0.3 avec une extension 0.4.
