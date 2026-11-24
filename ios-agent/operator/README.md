<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installer le panneau technicien 0.4.0

Le [complément 0.5.0](../docs/seance-050-fr.md) met à jour seulement
`ios-assist.html` et `ios-assist.js`. Le panneau indique quand la personne
masque son écran, efface l’image en direct et suspend les demandes de capture.
La conversation reste disponible pendant le masquage. Le plugin garde sa
version 0.1.0.

Le [complément 0.4.0](../docs/ipad-040-update-fr.md) ajoute l’âge de la dernière
image affichée, la durée restante si l’agent l’annonce et deux progressions de
transfert fondées sur les confirmations de réception. Les quatre fichiers web
doivent être mis à jour ensemble. Le plugin reste en 0.1.0. Les agents 0.3 restent
compatibles ; leur durée restante est indiquée comme non communiquée. Les tests
Node passent sous Windows ; la recette sur serveur et navigateur réels reste
nécessaire, ainsi que la validation de l’app et de l’extension sur iPad.

La mise à jour **console intégrée** est décrite dans
[la notice d’installation](../docs/assistance-console-update-fr.md).
Remplacez ensemble les quatre fichiers de ce panneau. Le guidage demande l’app
mise à jour ; une ancienne app conserve le chat mais n’active pas le guidage.
Dans l’app mise à jour, le menu s’appelle **Guidage, chat, documents, captures
et diagnostic**. Le démarrage rapide supprime la seconde confirmation du
technicien, après la préparation locale et le lancement système de la diffusion.

Ce dossier contient quatre fichiers originaux Apache-2.0, sans dépendance :
`ios-assist.html`, `ios-assist.js`, `ios-assist.css`, `ios-console.js`.
Ils complètent votre serveur existant ; aucun changement des handlers MeshCentral
ou de sa base de données n’est nécessaire.

1. Sur le serveur, repérez le dossier de personnalisation
   `meshcentral-web/public` utilisé par votre installation. Dans une installation
   npm classique, `meshcentral-web` se trouve à côté de `meshcentral-data`.
   Un domaine peut avoir un autre `webpublicpath` : utilisez alors ce dossier.
   Conservez les fichiers déjà présents ; seuls les quatre noms ci-dessus sont à ajouter.
2. Copiez ces quatre fichiers directement dans ce dossier `public`, sans
   remplacer tout le dossier et sans y copier le projet iOS ou les invitations.
3. Si vous venez de créer le dossier de personnalisation, redémarrez MeshCentral
   selon votre méthode habituelle : le serveur détecte ce dossier au démarrage.
4. Connectez-vous normalement à MeshCentral dans le navigateur du technicien.
   Ouvrez ensuite, dans le même navigateur, la page HTTPS
   `https://votre-serveur/ios-assist.html`. Pour un domaine avec préfixe d’URL :
   `https://votre-serveur/votre-domaine/ios-assist.html`.
   Pour vos tests, l’adresse attendue après installation est
   `https://mc.sdic.ch/ios-assist.html`.
5. Sur l’iPad, préparez et lancez la diffusion. Sélectionnez son nom dans le panneau
   puis **Demander une session**. En mode de validation séparée, acceptez ensuite
   **Autoriser cette assistance** dans l’app ; le démarrage rapide utilise l’accord
   donné pendant la préparation locale.
   Fermez une éventuelle session Desktop existante : un seul technicien à la fois.

Le panneau réutilise la session de connexion du navigateur et les droits du
compte. Aucun mot de passe, lien d’invitation ou jeton n’est à coller dedans.
Pour le chat, le compte doit posséder le droit **Chat / Notify**. Une restriction
**No files** interdit les documents. Le panneau ne contourne pas ces droits.

Le bouton Chat intégré à la fiche MeshCentral et l’onglet Files ne pilotent pas
ces fonctions : utilisez ce panneau pour les nouveautés 0.3.
L’onglet Desktop habituel continue à visualiser l’écran avec sa qualité adaptative.
Le chat et les documents nécessitent la session d’assistance autorisée ouverte.

## Console intégrée et nouvelles fonctions

Installez le [plugin local](../plugin/iosAssistance/README.md) pour accéder à
**Plugins → Assistance iOS** depuis la fiche de l’iPad. Le panneau vérifie que
l’appareil demandé figure dans la liste accessible à votre compte. Il ne bascule
pas vers un autre appareil si l’accès est absent. Le bouton de demande reste
inactif tant que l’agent n’annonce pas une connexion et la capacité de partage.

- Le tableau distingue l’app connectée, la diffusion prête, la demande, le relais,
  l’attente du consentement et la session active. Les indicateurs de présence ne
  remplacent jamais l’autorisation de l’utilisateur.
- **Bibliothèque de parcours** : cinq procédures de départ, modifiables dans le
  champ de guidage. Mémorisez un nouveau modèle, exportez la bibliothèque JSON
  pour la conserver et importez-la sur un autre poste. Limites : 25 modèles,
  20 étapes par modèle, 800 octets UTF-8 par étape, fichier de 256 Kio maximum.
- **Diagnostic** : interface réseau, faibles données, économie d’énergie,
  température et recommandation. Une absence de télémétrie ou d’images déclenche
  une indication distincte. Le RTT mesure le relais, pas le trajet complet jusqu’au
  technicien. Un chemin réseau disponible ne prouve pas que le serveur répond.
- **Affichage** : adaptation à la fenêtre, taille réelle et plein écran si le
  navigateur l’autorise.
- **Compte rendu** : export JSON des dates, événements et progression, limité à
  500 événements. Les messages, instructions et notes sont exclus par défaut ;
  cochez leur inclusion seulement si vous souhaitez les conserver. Aucune capture,
  contenu de document, adresse de connexion ou clé n’est ajouté automatiquement.
  Un texte libre peut contenir des informations personnelles si vous les saisissez.
  Exportez avant une nouvelle session, un rechargement ou un changement d’appareil.

Un rafraîchissement de la fiche conserve le flux. Quitter la page Plugins ferme
la session ; ouvrir une autre fiche détruit l’ancienne console. Revenir ne relance
pas automatiquement l’assistance. La bibliothèque et le compte rendu sont gardés
uniquement en mémoire de la page, sans stockage automatique dans le navigateur.

## Essayer les cinq fonctions

Dans l’app, ouvrez **Guidage, chat, documents, captures et diagnostic** après avoir accepté
la session. Le bouton rouge **Arrêter** reste disponible dans la barre supérieure.

1. **Chat :** envoyez un message depuis le panneau, répondez depuis l’app.
2. **Qualité :** observez FPS, kbit/s et RTT ; les trois profils changent
   automatiquement selon les mesures. Un profil maximal ne force pas
   l’agrandissement de la fenêtre du simulateur.
3. **Capture :** cliquez **Demander une capture** ; sur l’iPhone, confirmez
   **Autoriser l’envoi de cette capture** après examen de l’aperçu figé. Cliquez **Recevoir**
   dans le panneau, dessinez sur la capture, puis **Envoyer les annotations**.
   Elles apparaissent dans la section Capture de l’app.
4. **Documents :** choisissez un petit fichier (2 Mio maximum) dans le panneau,
   acceptez-le sur le téléphone, puis **Enregistrer… dans Fichiers**.
   Faites l’essai inverse avec **Choisir et envoyer un document** dans l’app,
   puis **Recevoir / Enregistrer le document reçu** dans le panneau.
5. **Diagnostic :** exportez le rapport JSON depuis chaque interface. Il ne
   contient ni invitation, ni clé, ni messages, ni documents.

Testez aussi le refus d’un fichier, l’annulation, puis **Terminer** :
les contenus temporaires sont effacés de l’interface. Les fichiers que vous
avez volontairement enregistrés restent à l’emplacement choisi.
Une nouvelle session nécessite un nouvel accord sur le téléphone.

La page doit être servie en HTTPS depuis le **même serveur et domaine** que
MeshCentral. Elle ne fonctionne pas en l’ouvrant avec `file://` ou sur un autre site.
Une erreur 404 indique un problème d’emplacement des quatre fichiers.
Une connexion fermée immédiatement peut indiquer une session navigateur expirée :
reconnectez-vous au serveur, puis rechargez le panneau.

Le panneau n’a pas été déployé sur votre serveur par cette tâche. Son protocole
est testé localement ; son rendu dans votre navigateur et la connexion réelle
avec l’app 0.3 restent à vérifier.
