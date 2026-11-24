<!-- SPDX-License-Identifier: Apache-2.0 -->
# Inventaire matériel iPad/iPhone — complément 0.4.2

Ce **candidat source à compiler et valider sur Mac/iPad** remplit l’onglet
**Détails / Details** : modèle technique, fabricant Apple, architecture et cœurs,
RAM et batterie lorsqu’elle est disponible. La version iPadOS provient toujours
des informations de connexion existantes. Le CPU figure dans **Motherboard /
Carte mère**, selon la présentation standard de MeshCentral.

L’inventaire est transmis à la connexion sécurisée et conservé par le serveur.
**Refresh / Actualiser** demande une nouvelle mesure si l’agent est connecté et
si le technicien possède les droits nécessaires. La batterie n’est pas suivie
en continu. Aucun partage d’écran n’est requis pour une connexion ordinaire.

## Appliquer le complément

1. La base requise est `MeshCentral-iOS-0.4.1-messenger-update.zip`, SHA-256
   `6f2457b3a62ad42cf2fe13fb68b78136a7d64d10f71956e578491dde1d99f2eb`.
   Si nécessaire, appliquez d’abord [la 0.4.1 et ses prérequis](messenger-041-update-fr.md).
   Une livraison précédente ne prouve pas son installation. Arrêtez la diffusion
   et sauvegardez votre projet configuré.
2. Décompressez `MeshCentral-iOS-0.4.2-hardware-inventory-update.zip`.
   Dans son dossier `MeshCentral-iOS-0.4.2-hardware-inventory-update`, vérifiez :

   ```sh
   python3 - <<'PY'
   import hashlib, json, pathlib
   for name, checksum in json.loads(pathlib.Path('SHA256SUMS-0.4.2.json').read_text()).items():
       path = pathlib.Path(name)
       assert not path.is_absolute() and '..' not in path.parts
       assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum, name
   print('Empreintes conformes')
   PY
   ```

3. Comparez puis fusionnez les fichiers fournis dans le projet existant, à la
   racine contenant `Cargo.toml`. Exemple depuis le dossier décompressé :

   ```sh
   rsync -av ./ "/chemin/vers/votre/projet/MeshCentral-iOS/"
   ```

   Adaptez le chemin et préservez vos modifications locales. Pas de `--delete`.
   Aucun fichier à supprimer/renommer. Aucun fichier serveur/plugin à remplacer.
4. Dans **votre** projet Xcode, mettez **Marketing Version à 0.4.2** pour l’app
   et l’extension, Debug et Release. Choisissez un même **Build**, supérieur à
   celui déjà utilisé. Gardez Team, Bundle IDs, App Groups, Keychain groups,
   profils, entitlements et préférences. Le ZIP ne remplace ni `.pbxproj`, ni
   plist, ni entitlements. Aucun ajout de permission ou référence Swift requis.
   **Ne lancez pas `generate_xcode.py`.**
5. **Reconstruisez la bibliothèque Rust**, sinon les symboles `mc_inventory_*`
   manqueront à l’édition de liens. Déplacez l’ancien
   `apple/Artifacts/MeshCore.xcframework` dans une sauvegarde distincte, sans
   écraser une sauvegarde existante. Avec les outils configurés selon
   [README-MAC](../README-MAC.md), lancez à la racine du projet :

   ```sh
   sh apple/build-xcframework.sh
   ```

   Le script refuse de remplacer une XCFramework existante. Il reconstruit les
   variantes appareil, simulateur Apple Silicon et macOS utilisées par ce projet.
   Ne remettez pas ensuite la bibliothèque 0.4.1.
6. Dans Xcode : **Clean Build Folder**, **Product → Test**, compilation des deux
   cibles pour appareil, puis archive Release. Les deux nouveaux tests XCTest
   sont dans le fichier de tests existant. Vérifiez les produits signés/groupes
   selon [le contrôle existant](ipad-sharing-preflight.md). Avant distribution
   binaire, contrôlez le rapport de confidentialité complet app/extension et
   les déclarations d’API à motif requis de votre projet. Aucun dépôt
   App Store/TestFlight n’est effectué par cette livraison source.
7. Installez ensemble l’app et son extension 0.4.2 sur l’iPad de validation.
   Conservez votre sauvegarde 0.4.1 pour revenir à cette version en reconstruisant
   et réinstallant ses deux cibles si nécessaire. Ne supprimez pas l’enrôlement.

`release-0.4.2.json` liste les changements et retouches manuelles. Le manifeste
local `dist/inventory-042-delivery.json` conserve les empreintes du ZIP, de sa
base et de tous les fichiers de la nouvelle référence.

## Recette sur iPad physique

| Essai | Résultat attendu |
| --- | --- |
| Connexion | Ouvrir l’app, lire l’information sur l’inventaire, toucher **Se connecter**, garder l’app au premier plan. Sur le site, ouvrir cet iPad → **Détails** : modèle technique, RAM, CPU, OS et batterie disponible apparaissent sans capture ni microphone. |
| Exactitude | Comparer modèle/iPadOS avec Réglages et le modèle technique avec l’appareil de test. RAM en MiB, cœurs retournés par iPadOS. Aucun nom de puce A/M, fréquence, IMEI, série ou stockage n’est inventé. |
| Batterie/actualisation | Brancher/débrancher l’alimentation, attendre au moins cinq secondes après la dernière demande, cliquer **Actualiser**. Vérifier pourcentage/état et date des détails. Une batterie indisponible est omise. Le cas 0 % est testé par fixture Windows : inutile de décharger l’iPad. |
| Droits | Un compte autorisé à voir les détails obtient le cache ; un compte sans ce droit ne reçoit pas l’inventaire. Actualiser exige aussi les droits habituels de routage distant du serveur. Ne pas élargir les droits pour contourner un refus. |
| ReplayKit | Démarrer un partage avec les consentements habituels. Après passage de la connexion à l’extension, les détails restent accessibles et Actualiser répond. Vérifier également le retour à la connexion de l’app. |
| Arrêt/interruption | Demander une actualisation puis déconnecter/arrêter immédiatement : aucune connexion ou assistance ne redémarre. Le cache reste visible avec sa dernière date. Reconnexion : nouvelle mesure et nouveau consentement obligatoire pour le partage. |
| Clics répétés | Aucun blocage ni file de demandes continuant après arrêt. Une seule opération en cours et une admission par cinq secondes ; réessayer après ce délai. |
| Non-régression | Vérifier partage consenti, arrêt local, Chat/Messenger au premier plan et guidage. Les validations 0.4.0/0.4.1 non encore effectuées restent nécessaires. |

Sur simulateur, vérifier séparément la mention **Simulator** et l’absence de RAM,
cœurs et batterie de l’hôte dans l’inventaire iPad. Il ne valide pas la collecte
matérielle sur un iPad physique.

Si l’onglet reste vide : vérifier que l’agent est celui de l’iPad et annonce
0.4.2, qu’il est connecté, que la bibliothèque Rust a été reconstruite, puis les
droits et l’actualisation après cinq secondes. Les données empruntent la connexion
`agent.ashx` authentifiée existante ; aucun port/plugin/endpoint supplémentaire
n’est attendu. Ne pas désactiver TLS.

Consignez Xcode/SDK, modèle/iPadOS, Version/Build des deux cibles, version/révision
du serveur et résultats de chaque ligne. Aucun test Mac, XCTest, simulateur ou
appareil physique n’a été exécuté depuis Windows.
