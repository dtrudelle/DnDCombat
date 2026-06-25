# Installation dans Xcode 26.3 — gestionnaire de combats D&D

## 1. Fichiers du projet

**À mettre dans la cible de l'app** (8 fichiers Swift + 1 ressource) :

| Fichier | Rôle |
|---|---|
| `DnDCombatApp.swift` | Point d'entrée (`@main`), les deux fenêtres, le menu Rencontre |
| `Monster.swift` | Modèle de bloc de monstre (décodage du JSON) |
| `DiceRoller.swift` | Lanceur de dés + résolution des attaques/saves |
| `Combat.swift` | Couche de combat : instances, groupes, PJ, Encounter, journal |
| `Library.swift` | Bibliothèque de monstres + état d'UI + utilitaires |
| `DMView.swift` | Fenêtre Maître du jeu |
| `MonsterPanelView.swift` | Panneaux de combat (PV, CA, saves, attaque) |
| `PlayerView.swift` | Fenêtre joueurs |
| `Sheets.swift` | Feuilles : ajout depuis biblio, import JSON, roster |
| `srd-2024-monsters.json` | **Ressource** : la bibliothèque SRD 2024 (331 monstres) |

**À NE PAS inclure** : les anciens fichiers du tout premier prototype (`Models.swift` notamment) — ils redéfinissent `Encounter` et provoqueraient un conflit.

**Optionnels** (référence/tests, hors cible) : `Demo.swift`, `CombatDemo.swift`, `monstre-format-exemple.json`.

## 2. Créer le projet

1. Xcode → **File ▸ New ▸ Project… ▸ macOS ▸ App**.
2. Product Name : `DnDCombat` · Interface : **SwiftUI** · Language : **Swift**. Créez le projet.
3. Xcode génère `DnDCombatApp.swift` et `ContentView.swift` :
   - **Supprimez** `ContentView.swift`.
   - **Remplacez tout le contenu** du `DnDCombatApp.swift` généré par celui du fichier fourni (il ne doit y avoir qu'un seul `@main`).

## 3. Ajouter les fichiers

1. Glissez les 8 fichiers `.swift` restants dans le navigateur de projet. Dans la boîte de dialogue : cochez **Copy items if needed** et la **cible** `DnDCombat`.
2. Glissez `srd-2024-monsters.json` de la même façon (Copy items + cible cochée).
3. Vérifiez : sélectionnez la cible → **Build Phases ▸ Copy Bundle Resources** → `srd-2024-monsters.json` doit y figurer. (Sinon, glissez-le-y.)

## 4. Réglages

1. Cible → **General ▸ Minimum Deployments ▸ macOS** : mettez **14.0** ou plus (le `@Observable` exige macOS 14+).
2. **Signing & Capabilities** : laissez la signature automatique avec votre Apple ID (gratuit), ou l'option « Sign to Run Locally ». Aucune autre capacité requise pour un usage local.

## 5. Lancer

1. Destination d'exécution : **My Mac**.
2. **⌘R**.
3. Deux fenêtres s'ouvrent : « Maître du jeu » et « Écran joueurs ». Glissez la fenêtre joueurs sur la TV et passez-la en plein écran (**⌃⌘F**). Le bouton **Écran joueurs** de la barre d'outils la rouvre/ramène au premier plan.

## 6. Première utilisation

1. Menu **Rencontre ▸ Roster des PJ…** : saisissez vos PJ (nom + bonus d'initiative).
2. Bouton **+ Monstre** (ou menu **Rencontre ▸ Ajouter un monstre…**) : piochez dans la bibliothèque, choisissez la quantité.
3. (Optionnel) **Importer** : collez un bloc JSON custom → il rejoint la bibliothèque **et** la rencontre.
4. **Lancer le combat** : l'app lance toutes les initiatives, trie, démarre le round 1.
5. En combat : `Tour suivant`/`Tour préc.`, les boutons **PV** (champ + −/+), la **CA** (stepper), les **6 saves**, le bouton **Attaque** (menu si plusieurs options), et les switches **Avantage/Désavantage**. Tous les jets s'affichent dans le **Journal**.

## Notes

- La couche logique (Monster, DiceRoller, Combat) a été compilée et testée. La couche **SwiftUI** n'a pas pu être compilée hors d'Xcode : si une erreur apparaît à la compilation, copiez-la, c'est corrigé en quelques minutes.
- **Module carte** (battlemap double écran) et **sauvegarde/chargement de rencontres** : prochaines étapes (la sauvegarde attendra le module carte, puisqu'une rencontre = carte + monstres).
- Attribution : les données proviennent du SRD 5.2 (CC-BY-4.0, Wizards of the Coast).
