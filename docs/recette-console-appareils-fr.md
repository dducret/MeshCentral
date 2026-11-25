<!-- SPDX-License-Identifier: Apache-2.0 -->

# Recette de la console et des appareils

## Parcours de référence

La console Bootstrap de MeshCentral ouvre « My Devices » après connexion sur
une session neuve. Le filtre textuel et le filtre d’état réduisent les appareils
affichés. Le nom d’un appareil ouvre sa fiche « General ». Le bouton Retour
revient à la vue précédente et conserve le filtre si cette vue est la liste.
Les variantes Colonnes et Liste, les groupes, les tris, les sélections et les
actions disponibles dépendent des réglages et des données de la session.

Le lot s’applique au gabarit Bootstrap `default3`, sélectionnable sur l’instance
de test avec `?sitestyle=3`. La navigation conserve les modes latéral et empilé
de MeshCentral. Le lot utilise les composants, les icônes et les polices système
déjà présents. Impeccable a servi de référence de conception. Les ajouts
sont sous Apache-2.0. [Impeccable](https://github.com/pbakaus/impeccable)

## Critères réutilisables

Préparer un compte opérateur sur une instance isolée avec au moins deux appareils
fictifs aux noms distincts, dont un est hors ligne. Pour la couverture des droits,
préparer aussi un compte limité à un sous-ensemble des appareils et des actions.

| Étape | Résultat observable |
| --- | --- |
| Ouvrir la console authentifiée | La liste apparaît et la navigation signale la section courante. Les rubriques reflètent les droits du compte. |
| Saisir une partie d’un nom puis combiner avec le filtre d’état | Les résultats correspondent aux deux filtres. Les préfixes et opérateurs de recherche existants, par exemple `g:`, `t:`, `and` et `!`, gardent leur sens. |
| Rechercher un nom absent puis effacer la recherche | Le message d’absence de résultat propose une action utilisable au clavier. Effacer le texte rend la main au champ et conserve le filtre d’état. |
| Activer le nom d’un appareil | « General » identifie l’appareil et son groupe. Le statut hors ligne est lisible en texte. Un appareil local sans agent garde le traitement des appareils locaux. |
| Comparer les commandes avec le compte limité | Les appareils accessibles, les sous-onglets et les actions d’édition ou d’assistance suivent les droits existants. Ouvrir « General » laisse les actions d’assistance en attente d’une commande explicite. |
| Utiliser Retour | La liste affiche le même filtre et le même type de vue. Le focus revient au champ de recherche de la vue. |
| Parcourir à 1 280 px puis à 520 px | La navigation, la liste et la fiche restent dans la largeur disponible. Les noms et leur focus sont visibles dans le tableau. Si des colonnes supplémentaires dépassent, le défilement reste dans le tableau. Les onglets d’appareil restent accessibles. |
| Répéter les activations au clavier | Tab et Maj+Tab suivent l’ordre des commandes. Entrée ouvre le lien d’un appareil. Entrée et Espace activent les boutons natifs. Le focus reste visible. |
| Mesurer les couleurs rendues | Le texte courant retouché atteint 4,5:1 et le contour de focus mesuré atteint 3:1 contre la surface adjacente. |

## Interfaces à conserver pour la phase Rust

- `go()`, `gotoDevice()` et `goBack()` pilotent la présentation et reprennent
  les identifiants d’appareil et de groupe, la vue courante et la pile de retour.
- `onDeviceSearchChanged()` synchronise le texte de recherche entre les modes de
  liste. `onSearchInputChanged()` calcule les résultats affichés et la requête
  `nodes` conserve sa forme pour le filtrage côté serveur.
- `GetMeshRights()` et `GetNodeRights()` alimentent les conditions d’affichage à
  partir de la session et des données du serveur. Les vérifications du serveur
  restent l’autorité pour chaque commande.
- L’ouverture de la fiche réutilise les requêtes existantes d’alimentation de la
  vue, dont `powertimeline`, `lastconnect`, `getsysinfo`, `getNotes` et
  `deviceShares`. Les commandes d’assistance gardent leurs points d’entrée et
  les règles de consentement de MeshCentral.

## Base technique

Révision locale `67aff175f6d1093b1a81f8e9230607854d3fbaa6` sur `master`.
Le dépôt officiel est `upstream` et sa branche par défaut est `master`.
Le dossier Git en lecture seule a bloqué le fetch et la création de
`codex/web-navigation-devices`. Les changements sont dans le workspace.

## Vérification du lot

- Sous Windows, `git diff --check` et
  `node translate/translate.js check views/default3.handlebars` ont abouti.
  Le traducteur a relevé 2 730 chaînes.
- Edge en mode sans interface, avec un profil temporaire, a exécuté la recette
  sur MeshCentral 1.3.1 en local. Le jeu de test contient trois appareils fictifs
  dans deux groupes. La navigation principale au clavier, la recherche par nom,
  l’ouverture de la fiche par Entrée, le retour par Espace, la conservation du
  filtre et son effacement au clavier ont abouti.
- Le rendu en Colonnes et la fiche ont été inspectés à 1 280 et 520 px. Les
  textes échantillonnés en thème clair ont obtenu de 6,41:1 à 14,02:1.
  Le focus du champ de recherche a obtenu 5,66:1. En thème sombre, sur la liste,
  le nom et le statut d’appareil ont obtenu 9,88:1 et 9,33:1.

### Complément avec un compte restreint

- Une passe Edge sur l’instance locale a couvert le mode Liste et le thème
  sombre à 1 280 et 520 px. Le compte sans droits d’administration du site
  avait le droit de consulter l’inventaire d’un seul groupe sur les deux
  groupes fictifs. Seuls ses deux appareils apparaissaient. L’onglet Details
  était accessible. Les onglets Desktop, Terminal, Files et Console ainsi que
  le renommage et les actions d’administration de l’appareil étaient masqués.
- Le filtre Offline s’est combiné avec `g:Offline and Lyon`. La recherche
  visant le groupe hors périmètre a affiché le résultat vide. L’effacement au
  clavier a conservé le filtre d’état. Entrée a ouvert la fiche de l’appareil
  et Espace a ramené à la liste en conservant le mode, les deux filtres et le
  focus dans la recherche.
- À 520 px, la première colonne comprimait le lien de l’appareil jusqu’à
  masquer son nom. La correction réserve la place du nom et réduit les
  marges décoratives. La reprise ciblée a confirmé que les deux noms
  fictifs restaient lisibles, que le focus du lien était visible et que les
  colonnes supplémentaires défilaient à l’intérieur de la liste.
- En thème sombre, les textes échantillonnés dans la liste et la fiche ont
  obtenu au moins 7,43:1. Le contour de focus de Retour a obtenu 12,75:1.

### Contraste de l’en-tête du tableau de puissance

Le contrôle ciblé dans Edge, à 1 280 et 520 px, a mesuré un contraste de
1,78:1 avant correction et de 11:1 après correction pour les deux libellés
et l’icône de téléchargement en thème sombre. La comparaison des styles
calculés a confirmé le même rendu des lignes du tableau avec et sans le
correctif, ainsi que le même rendu de l’en-tête en thème clair.

## Console 2026 et accès par URL

Avant ce lot, ouvrir une fiche remplaçait la liste et plaçait les onglets
d’appareil dans la barre supérieure. La console Bootstrap affiche maintenant
la fiche à côté de la liste à partir de 1 120 px en mode Colonnes ou Liste,
sur un écran de bureau. Les onglets Général, Événements et Détails utilisent
leurs panneaux MeshCentral existants. Le bouton « Open full page » agrandit
la fiche. Sur mobile, la fiche occupe d’emblée la largeur de la console.
Les outils de session et les liens directs continuent d’ouvrir leur panneau
dédié. La navigation de bureau affiche les libellés et le tableau distingue
la sélection et la connectivité.

Ajouter `"webUiV2": true` à l’objet du domaine existant dans
`meshcentral-data/config.json`, généralement `domains[""]`, puis redémarrer
MeshCentral. L’option est illustrée dans `sample-config-advanced.json`.

- Sur le même domaine, `/` ouvre par défaut la console historique et
  `/v2` ouvre la console Bootstrap. `/v2/` redirige vers `/v2`.
  Les liens existants avec `?sitestyle=3` restent valides.
- Les deux adresses utilisent les mêmes comptes, listes d’appareils, droits,
  cookies de session et préférences. Les ressources et `control.ashx`
  restent à la racine du domaine. Le proxy doit transmettre `/v2` à
  l’instance MeshCentral existante.
- Les domaines qui laissent l’option désactivée continuent à sélectionner
  leur interface selon leurs réglages habituels. Un domaine à chemin qui
  porte déjà l’identifiant `v2` garde ce chemin.

### Critères complémentaires

| Étape | Résultat observable |
| --- | --- |
| Ouvrir `/v2/` sans session et se connecter | L’adresse devient `/v2` et le formulaire utilise l’authentification du domaine. |
| Filtrer la liste sur un écran large et ouvrir un appareil au clavier | La liste reste visible et filtrable, la sélection est signalée et le focus atteint le titre de la fiche. |
| Changer d’onglet avec un compte restreint | Les onglets autorisés restent accessibles dans la fiche latérale et les outils réservés suivent les droits existants. |
| Agrandir la fiche puis revenir | La liste retrouve le mode, le filtre de texte, le filtre d’état et le focus de recherche. |
| Alterner entre `/v2` et `/` | La session du même compte, ses droits et ses filtres sont repris par les deux interfaces. |
| Ouvrir la fiche sur mobile et revenir | La fiche prend la largeur de l’écran et le retour restitue la liste filtrée. |

### Résultat de la recette 2026

- Sur MeshCentral 1.3.1 en local, Edge a affiché le formulaire de connexion
  après redirection de `/v2/` vers `/v2`. À 1 280 px, le compte restreint
  a ouvert la fiche latérale au clavier, affiné les résultats pendant que
  la fiche était ouverte, puis utilisé les onglets Détails et Événements.
  Les onglets d’assistance réservés étaient masqués. L’agrandissement et le
  retour ont préservé le mode Liste, les deux filtres et le focus.
- Le premier passage vers la console historique a révélé une erreur de
  syntaxe JavaScript dans un message de compatibilité. Après correction,
  la reprise ciblée a validé les deux bascules d’interface avec le même
  compte et les mêmes filtres. Le domaine témoin à chemin sans l’option a
  répondu 404 à sa route `v2`.
- En émulation tactile à 390 px, la fiche et la barre d’onglets ont occupé
  les 390 px disponibles. Le retour a réaffiché les résultats avec les
  filtres conservés. Le contraste du texte échantillonné sur la navigation,
  la sélection et l’état a dépassé 4,5:1.
- La syntaxe de `webserver.js`, le JSON des deux fichiers de configuration,
  le contrôle de traduction des deux gabarits et `git diff --check` ont été
  vérifiés sous Windows. La recette concerne l’instance locale et son
  authentification intégrée.

### Recette du lot préparé depuis upstream

Sur `7d52d950` sous Windows, le lot `web-ui-v2` a modifié uniquement
`webserver.js` parmi les sources upstream. Il a généré
`default3-v2.handlebars` à part, ainsi que ses variantes française et
minifiées avec le traducteur MeshCentral. Le contrôle de préparation a
accepté la base propre et la copie déjà préparée.

Dans Edge, la première tentative s’est arrêtée avant l’ouverture du
navigateur pendant la signature initiale des agents de l’instance de test.
La recette relancée après le premier démarrage a vérifié le parcours
avec le compte restreint et l’authentification MeshCentral intégrée.

- `/v2/` redirige vers `/v2` et présente le formulaire de connexion.
  Le domaine témoin sans `webUiV2` renvoie 404 sur sa route `v2`.
- À 1 280 px en mode Liste, le clavier ouvre la fiche latérale et place
  le focus sur son titre. Les filtres restent modifiables et les onglets
  réservés suivent les droits existants. L’agrandissement et le retour
  préservent le mode, les filtres et le focus.
- Les boutons de bascule entre les deux adresses retrouvent le même compte
  et les mêmes filtres. À 390 px en émulation tactile, la fiche occupe
  toute la largeur et son bouton de retour restaure la liste filtrée.
- Les contrastes mesurés étaient de 8,32:1 pour la navigation active,
  7,44:1 pour l’appareil sélectionné et 6,41:1 pour l’état de la fiche.
  La recette n’a relevé aucune exception JavaScript.

### Paquet npm officiel 1.3.1

Le ZIP de correction accompagne le premier lot `web-ui-v2`. Sur le paquet
officiel `meshcentral@1.3.1`, le contrôle d’origine échouait sur le contexte
de la colonne Connectivité. Le correctif utilise le contexte commun aux
deux gabarits et sélectionne un patch serveur adapté au paquet npm.

- Le contrôle de préparation a accepté le paquet npm intact, sa copie
  préparée et la branche du fork sur `7d52d950`. Le paquet d’origine a été
  vérifié avec la somme d’intégrité publiée par npm.
- Le contrôle de syntaxe serveur et la génération des variantes minifiée
  et française ont abouti. Parmi les fichiers du paquet npm, seul
  `webserver.js` a été modifié. La console 2026 est générée séparément.
- Dans Edge sous Windows, le compte restreint s’est connecté depuis `/v2`
  et a retrouvé la même session et les mêmes filtres après bascule vers `/`
  puis retour. La fiche latérale s’est ouverte au clavier à 1 280 px.
  À 390 px, la fiche et ses onglets occupaient toute la largeur. La recette
  n’a relevé aucune exception JavaScript.

L’authentification de cette recette était celle intégrée à MeshCentral.

### Activation sur mc.sdic.ch

Le 24 novembre 2026, le contrôle de préparation et l’installation du lot
npm ont abouti. La première tentative d’accès à `/v2` a renvoyé 404 car
`webUiV2` figurait dans `settings`. Après déplacement de l’option
`"webUiV2": true` dans `domains[""]` et redémarrage de MeshCentral,
l’exploitant a confirmé la redirection `307` de `/v2/` vers `/v2` et
l’accès à la console 2026. La recette détaillée avec le compte restreint
correspond à l’instance de test locale décrite ci-dessus.

### Réapplication depuis Git

Le lot réuni a été appliqué avec `git am` sur une copie de `7d52d950`.
Le contrôle de préparation depuis un checkout Windows en CRLF a accepté
cette révision et le paquet npm officiel 1.3.1. La lecture des patchs
convertit leurs fins de ligne en LF avant de les transmettre à Git.

### En-tête, pied de page et actions de groupe sur `/v2`

Le 25 novembre 2026, la reprise part du commit `d1de8ab3` du fork.
Les modifications de présentation sont dans le patch du gabarit Bootstrap
et sa feuille de style. Les commandes groupe utilisent les filtres de
droits et les dialogues déjà présents dans MeshCentral.

| Étape de la recette | Résultat attendu |
| --- | --- |
| Ouvrir `/v2` avec un compte restreint | L’en-tête contient le nom du serveur et le menu du compte. La vérification d’adresse e-mail apparaît dans l’en-tête lorsque le compte la permet. |
| Sélectionner, replier puis rouvrir un groupe | Le nom donne accès à la fiche du groupe et le chevron indique l’état du groupe au clavier. Le compteur suit la liste affichée. |
| Comparer un groupe modifiable à un groupe en lecture seule | Le menu du premier expose les actions permises par son type et ses paramètres. Le second n’affiche aucune commande d’ajout. Les boutons ouvrent les dialogues MeshCentral. |
| Passer en thème sombre puis ouvrir la liste sur mobile | Les couleurs restent lisibles. À 390 px, le menu compact est utilisable et le lien légal est accessible depuis le compte. |
| Consulter `/` depuis la même session | L’interface historique s’ouvre avec le même compte. |

- `prepare.cjs --check` a accepté la base upstream `7d52d950` et le paquet
  npm officiel `meshcentral@1.3.1`. La génération du gabarit minifié et de
  sa version française a abouti avec le traducteur MeshCentral.
- La recette Edge sur npm 1.3.1 a utilisé un compte sans droit
  d’administration du site, avec droit d’ajout sur un seul groupe. En
  mode Liste à 1 280 px, le clavier a replié le groupe, ouvert le menu
  d’actions et restauré le focus avec Échap. Les dialogues d’ajout et
  d’invitation se sont ouverts. Aucune commande d’ajout n’était affichée
  dans le groupe en lecture seule.
- La reprise ciblée après correction de l’ouverture du menu du compte a
  validé l’accès au clavier, le pied de page personnalisé, le menu mobile
  sur le rendu français minifié et la bascule vers `/` avec la même session.
  Le contraste mesuré du compte, du lien légal et du bouton de groupe
  était compris entre 8,32:1 et 14,02:1 en clair, et entre 9,44:1 et
  13,55:1 en sombre. Aucune exception JavaScript n’a été relevée.

### Mire de connexion et actions près du compteur sur `/v2`

Le 25 novembre 2026, la reprise part du commit `263b94e2`. Les actions
autorisées suivent le compteur dans les en-têtes de groupe, y compris
lorsque le groupe est vide. La mire `/v2` utilise une feuille de style
dédiée sur les gabarits de connexion MeshCentral existants.

- La préparation a accepté la base `7d52d950` et le paquet npm officiel
  1.3.1. Sur une copie npm qui servait déjà `/v2`, elle a ajouté le patch
  de connexion. Le contrôle est aussi passé après installation. Les
  variantes minifiée et française de `default3-v2` ont été générées.
- Dans Edge sur npm 1.3.1, le formulaire a été validé au clavier à
  1 280 px en clair et à 390 px en sombre sur le rendu français minifié.
  Un mot de passe erroné a affiché une erreur lisible. La reprise ciblée
  après correction du contraste du champ minifié a validé le formulaire,
  la saisie d’un code TOTP réel du compte synthétique et l’ouverture de
  la console. Le contraste mesuré des champs et du bouton a atteint au
  moins 8,32:1, et le message d’erreur a mesuré 7,05:1.
- Le bouton de groupe était à 8 px du compteur dans le groupe rempli
  sur les deux largeurs, et dans le groupe vide au bureau. Le menu a
  fonctionné au clavier et au toucher. Le groupe en lecture seule
  n’affichait aucune action d’ajout. La mire de `/` avait sa présentation
  habituelle et la session ouverte sur `/v2` y restait active.
- La recette concerne l’authentification MeshCentral intégrée avec TOTP.
  Aucune exception JavaScript n’a été relevée sur le parcours testé.
