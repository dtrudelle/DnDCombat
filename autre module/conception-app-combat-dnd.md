# Application de gestion de combats D&D 5e — Conception

## Principe directeur
Outil minimaliste pour MJ : garder le strict nécessaire, retirer la lourdeur de Roll20.
App macOS 15 non publiée, usage personnel. Figurines physiques posées sur une TV à plat.

## Pile technique
- **Swift / SwiftUI natif** (macOS 15), avec un peu d'AppKit pour le multi-fenêtre.
- **Un seul modèle de données partagé** (`@Observable`), injecté via `environment`, observé par les deux fenêtres → synchronisation automatique (déplacer/modifier côté MJ se reflète côté joueur).
- **Données persistantes en local** (JSON ou SwiftData) : bibliothèque de monstres, roster de PJ, rencontres.

## Les deux fenêtres
- **Fenêtre MJ** : panneau de contrôle (cf. maquette validée en conversation, v3).
- **Fenêtre joueur** (2ᵉ écran, TV à plat) : grande carte verrouillée + initiative en **lecture seule**.

---

## Module 1 — Battlemap
- Import d'une **image de décor brute** par rencontre.
- **Grille dessinée par l'app** en surimpression (image décor pure dessous). Nombre de cases réglable.
- **Calibration physique unique** à la TV : on règle l'échelle pour qu'une case ≈ 1 pouce réel (≈ 25,4 mm), pour que les figurines tombent juste. Tracer un trait de 100 mm, mesurer à la règle, ajuster.
- **Zoom = mise en place uniquement** : on cale au début, on verrouille, on n'y touche plus pendant le combat (figurines posées). Pas de zoom live. Les maps sont préparées à un nombre de cases fixe calibré pour la TV → le zoom est quasi superflu (« ajuster à l'écran »).
- **Même échelle des deux côtés** (même facteur d'échelle, pas le même cadrage au pixel).
- **Indicateur MJ** : « Affichage joueur : 28 × 18 cases · case ≈ 25,4 mm ».
- **Côté MJ**, la carte est une simple **vignette dans un coin** ; le rendu soigné ne concerne que la fenêtre joueur.
- **Exclu** : gestion de tokens, brouillard de guerre.

## Module 2 — Initiative
- **Liste** = PJ + groupes de monstres, triée par initiative décroissante, combattant actif surligné, compteur de round.
- **Roster de PJ permanent** : nom + bonus d'init, saisi une fois. L'**app lance** l'init des PJ (1d20 + bonus). Les PJ ne sont pas stockés dans une rencontre (ils viennent du roster global).
- **Monstres** : init lancée par l'app (1d20 + DEX), **un seul jet par groupe** (les monstres identiques partagent une ligne).
- **Bouton unique « Lancer le combat »** : lance toutes les inits (PJ + monstres), trie, met le round 1, active le premier. Avant le combat, il occupe la place de la barre ; pendant, la barre montre `‹ Tour préc.` · `Round N` · `Tour suiv. ›`.
- **Tour précédent / Tour suivant** : avance/recule d'un cran ; en bord de liste, gère le passage de round.
- **Switches Avantage / Désavantage** dans la barre : quand l'un est ON, les jets de d20 (saves + toucher) sont doublés → meilleur (ou pire) résultat. Les deux ON = jet normal (règle 5e).
- Toutes les valeurs d'init restent **éditables à la main** (égalités, cas spéciaux).
- **0 PV** = monstre marqué hors-combat. **Pas d'états, pas d'inconscient, pas de jets de mort.**
- Affichée en **lecture seule** sur l'écran joueur.

## Module 3 — Monstres (panneau de combat)
Une **instance par créature** (Gobelin 1, 2, 3, 4), même si l'initiative les regroupe sur une ligne. Plusieurs créatures **dépliables en même temps** ; l'active se déplie automatiquement.

Éléments visibles / interactions par créature :
- **PV** : « courant / max », champ libre pour une valeur + boutons **−** / **+** qui la retranchent/ajoutent. Les boutons PV restent présents même sur une **ligne repliée**.
- **CA** : clic dessus = appliquer un **bonus/malus** temporaire.
- **Vitesse** : toujours visible (consultatif), en **feet**.
- **6 boutons de sauvegarde** (FOR DEX CON INT SAG CHA) : clic = l'app lance 1d20 + modificateur (dérivé des caractéristiques + maîtrises) et affiche le résultat.
- **Nom cliquable** → menu déroulant : traits (capacités non-offensives), résistances/immunités.
- **Bouton Attaque** (cf. ci-dessous).

### Comportement du bouton Attaque
- L'app lance les dés et donne les résultats.
- **Une seule action offensive** → lancée directement (toucher + dégâts, ou dégâts + DD).
- **Multiattaque** → **toujours la séquence complète d'un coup** (chaque composante donne son résultat).
- **Popup** seulement s'il y a de vraies **alternatives** (ex. multiattaque corps-à-corps vs souffle) ; on choisit l'action, puis elle se lance en entier.
- **Attaque au toucher** : 1d20 + bonus vs CA, puis dégâts.
- **Attaque à sauvegarde** : pas de toucher → l'app lance les **dégâts** et affiche le **DD** (« DD 15 DEX, demi si réussite »).
- **Effet sans dégât** : champ `effect` affiché avec le résultat (s'applique au toucher si `tohit`, sur échec si `save`).

## Lanceur de dés
- Jets : 1d20 + modificateur (saves, toucher), dégâts `XdY+Z` par composante, **additionnées** par type.
- **Avantage/désavantage** : double le d20, garde meilleur/pire ; les deux ON = jet normal.
- Tous les résultats atterrissent dans le **journal des jets** (log persistant, bas-droite de la fenêtre MJ).

---

## Formats de données

### Bloc de monstre
Format JSON unique partagé par : import SRD, saisie manuelle, dés de l'app, et blocs custom Thalaris.
Voir le fichier de référence **`monstre-format-exemple.json`**.
Champs clés : `name, size, type, cr, proficiencyBonus, ac, hp{average,formula}, speed, abilities, saveProficiencies, damageResistances/Immunities, conditionImmunities, traits[], attacks[], attackOptions[]`.
- `abilities` + `saveProficiencies` → l'app **dérive** les 6 modificateurs de save.
- `damage` = **liste de composantes** (gère « 2d8+4 contondant + 1d6 feu »).
- `attacks` = définitions ; `attackOptions` = menu du bouton (1 = direct, >1 = popup ; un élément `multiattack` porte sa `sequence`).
- PV courants et delta de CA ne sont **pas** dans le bloc : ce sont des états **par instance** en combat.

### Rencontre (modèle réutilisable)
`{ name, mapImageRef, gridConfig, monstres: [{ blockId, count }] }`
- **Ne contient pas** les PJ (roster global).
- Au chargement : **repart à neuf** (full PV, init non lancée).

### Roster de PJ (permanent)
`[{ name, initBonus }]` — saisi une fois, réutilisé à chaque combat.

### Bibliothèque de monstres (persistante)
Contient le **SRD 2024 (SRD 5.2)** pré-chargé + les monstres custom.
- **Source** : API **Open5e V2**, document `srd-2024` → `https://api.open5e.com/v2/creatures/?document__key__in=srd-2024`. Le SRD 5.2 (règles 2024) est sous **CC-BY-4.0**, donc embarquable. (`srd-2014` reste dispo pour la 5e 2014 ; 5e-bits/5e-database n'a pas encore le 2024.)
- **Limites** : le SRD 5.2 est un **sous-ensemble** du Monster Manual 2024 (pas les créatures « marque » : Strahd, Orcus, Tiamat…). Données communautaires → **valider à l'import**. Les attaques au toucher arrivent structurées ; les attaques à **sauvegarde** ont leur mécanique en texte (`desc`) → léger parsing/retouche.
- **Ajout de monstres (dans l'interface de rencontre) — deux boutons** :
  - **« + »** : ouvre la **bibliothèque** pour sélectionner un monstre (+ quantité) → ajout à la **rencontre en cours**.
  - **« Importer »** : coller un bloc JSON (notre format) → ajout à la **bibliothèque + la rencontre en cours** (pipeline Thalaris : bloc généré → collé → utilisable immédiatement).
  - Pas de formulaire de saisie manuelle : les monstres custom entrent dans la bibliothèque **via Importer** (blocs JSON générés au fil des aventures Thalaris).

## Flux — menu « Rencontre » (barre de menu macOS)
- **Créer** : importer la map + piocher les monstres dans la biblio (quantités). C'est ici que vit le flux biblio → combat.
- **Sauvegarder** : enregistre la rencontre (modèle) sous un nom.
- **Charger** : ramène une rencontre dans la vue de combat (repart à neuf).
- **Effacer** : supprime une rencontre (avec confirmation).

---

## Ordre de construction suggéré
1. **Initiative** (MVP en cours) → étendre avec le roster de PJ et le bouton « Lancer le combat ».
2. **Bloc de monstre + lanceur de dés** : modèle, import SRD, panneau de combat (PV, CA, saves, attaque).
3. **Bibliothèque + rencontres** (CRUD, menu macOS).
4. **Battlemap double écran** : fenêtre joueur, grille calibrée, verrouillage.
