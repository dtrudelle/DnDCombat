# Format des blocs de monstre — projet Thalaris

Référence de format pour les monstres de l'app de combat. À déposer dans la
**connaissance du projet** : je pourrai alors produire des blocs conformes à tout moment.

> Astuce fiabilité : déposez **aussi** `Monster.swift` dans la connaissance du projet,
> pour que je puisse décoder/valider chaque bloc livré.

---

## 1. Comment on travaille

- Vous me demandez un ou plusieurs monstres (« fais-moi un griffon des brumes FP 5 »).
- Je réponds avec un bloc `{ … }` ou un tableau `[ … ]`.
- Vous collez dans **Bibliothèque de monstres ▸ Importer…** (objet seul **ou** tableau).
  Les blocs importés deviennent des monstres **« maison »** (éditables, persistés).

L'app **dérive** tout ce qui peut l'être à partir des caractéristiques et du bonus de
maîtrise : modificateurs de carac et de sauvegarde, **bonus au toucher**, **DC**, et
**bonus de dégâts**. Vous ne fournissez donc jamais ces valeurs — seulement la carac
régissante de chaque attaque.

---

## 2. Schéma du monstre

| Champ | Type | Requis | Notes |
|---|---|---|---|
| `id` | texte | oui | identifiant unique, ex. `"thal-archonte-cendres"` |
| `name` | texte | oui | nom affiché |
| `size` | texte | oui | libre, ex. `"TP" "P" "M" "G" "TG" "Gig"` |
| `type` | texte | oui | libre, ex. `"bête" "mort-vivant" "élémentaire"` |
| `cr` | nombre | oui | fractions admises : `0.125 0.25 0.5 1 2 …` |
| `proficiencyBonus` | entier | oui | voir la table §5 |
| `ac` | entier | oui | classe d'armure |
| `hp` | objet | oui | `{ "average": 110, "formula": "13d10+39" }` |
| `speed` | objet texte→texte | oui | clés anglaises, ex. `{ "walk": "30 ft", "fly": "60 ft" }` |
| `abilities` | objet | oui | les six : `{ "FOR":18,"DEX":14,"CON":18,"INT":12,"SAG":14,"CHA":16 }` |
| `saveProficiencies` | liste de codes | oui | carac maîtrisées en sauvegarde, ex. `["DEX","CON"]` — peut être `[]` |
| `damageResistances` | liste de textes | non | en **anglais**, ex. `["fire","cold"]` |
| `damageImmunities` | liste de textes | non | en **anglais** |
| `damageVulnerabilities` | liste de textes | non | en **anglais** |
| `conditionImmunities` | liste de textes | non | états en **anglais**, ex. `["Poisoned","Exhaustion"]` |
| `traits` | liste d'objets | non | `{ "name": …, "description": … }` (voir §4) |
| `attacks` | liste d'attaques | oui | catalogue des attaques (peut être `[]`) |
| `attackOptions` | liste d'options | oui | ce que propose le bouton Attaque (peut être `[]`) |

Codes de caractéristiques (toujours en français) : **`FOR DEX CON INT SAG CHA`**.

---

## 3. Une attaque (`attacks[ ]`)

| Champ | Type | Requis | Notes |
|---|---|---|---|
| `name` | texte | oui | référencé par les options |
| `kind` | `"tohit"` ou `"save"` | oui | jet au toucher, ou attaque à sauvegarde |
| `ability` | code de carac | **oui** | **carac régissante** : dérive le toucher, le DC et le bonus de dégâts (voir §3a) |
| `addAbilityToDamage` | booléen | non | ajoute le mod de la carac régissante à la **1ʳᵉ** composante de dégâts (voir §3a) |
| `actionType` | `action` / `bonus` / `reaction` / `legendary` | non | descriptif (défaut : `action`) |
| `reach` | texte | non | ex. `"5 ft"` — n'apparaît au journal que si ≠ `"5 ft"` |
| `range` | texte | non | ex. `"80/320 ft"` |
| `save` | objet | oui si `save` | `{ "ability": "DEX" }` — carac de save **de la cible** (le DC est dérivé) |
| `area` | texte | non | ex. `"cône de 9 m"` |
| `damage` | liste | non | composantes ; **dés sans modificateur** (voir §3a) |
| `halfOnSave` | booléen | non | demi-dégâts si la sauvegarde réussit |
| `condition` | texte | non | état infligé, **nom anglais** (voir §3b) |
| `effect` | texte | non | description longue (durée, save répété…) — hors journal |
| `recharge` | texte | non | ex. `"5-6"` — informatif |

Une **composante de dégâts** : `{ "dice": "2d6", "type": "slashing" }`.
Les **types de dégâts sont en anglais** : `acid bludgeoning cold fire force lightning
necrotic piercing poison psychic radiant slashing thunder`.

### 3a. Dérivation (toucher, DC, dégâts) — ne fournissez jamais de valeur figée

Tout repose sur `ability` (la carac régissante) + `proficiencyBonus` + `abilities` :

- **Bonus au toucher** (attaque `tohit`) = `mod(ability) + proficiencyBonus`.
- **DC** (attaque `save`) = `8 + mod(ability) + proficiencyBonus`.
- **Bonus de dégâts** : si `addAbilityToDamage: true`, on ajoute `mod(ability)` à la
  **première** composante de dégâts uniquement (jamais doublé au critique).

Conséquence : **les dés ne contiennent pas de modificateur** (`"2d6"`, pas `"2d6+4"`)
et il n'y a **plus** de champ `toHit` ni de `dc` dans `save`. Si vous modifiez une carac
ou le bonus de maîtrise dans l'app, toucher / DC / dégâts se recalculent seuls.

Choix de `ability` selon le type d'attaque :
- **mêlée d'arme** → `FOR` (ou `DEX` si finesse), avec `addAbilityToDamage: true` ;
- **distance d'arme** → `DEX`, avec `addAbilityToDamage: true` ;
- **sort / capacité** → la carac d'incantation (`INT`, `SAG` ou `CHA`) ;
  `addAbilityToDamage` selon que les dégâts ajoutent ou non le mod (souvent `true`
  dans le SRD 2024 pour les attaques de sort, `false`/absent pour les souffles de zone) ;
- **souffle / save physique** → souvent `CON` (ex. souffle de dragon) ; la carac que
  **la cible** jette va dans `save.ability` (souvent `DEX`).

> `ability` (la carac qui régit l'attaque) et `save.ability` (la sauvegarde de la cible)
> sont **indépendantes** : un souffle peut être régi par `CON` (pour le DC) tout en
> demandant une sauvegarde de `DEX` à la cible.

### 3b. Champ `condition` (états infligés)

`condition` = le **nom anglais court** de l'état, affiché de façon compacte au journal :
`DD 15 SAG → Frightened` (save) ou `… = 14 dégâts → Grappled` (toucher). La réussite de
la sauvegarde annule — l'app ne le précise pas. Détails longs (durée, save répété, DC
d'évasion) dans `effect`, rédigeable en français.

**Les 15 états standard** (valeurs admises) : `Blinded`, `Charmed`, `Deafened`,
`Exhaustion`, `Frightened`, `Grappled`, `Incapacitated`, `Invisible`, `Paralyzed`,
`Petrified`, `Poisoned`, `Prone`, `Restrained`, `Stunned`, `Unconscious`.

---

## 4. Les options d'attaque (`attackOptions[ ]`)

Les boutons proposés. Deux types :

- **Attaque simple** — `{ "type": "single", "attack": "Souffle de cendres" }`
  (`attack` doit correspondre **exactement** à un `name` de `attacks`).
- **Multiattaque** —
  `{ "type": "multiattack", "description": "Deux griffes", "sequence": [ { "attack": "Griffe ardente", "count": 2 } ] }`

> **Traits, actions légendaires, réactions** : pas de champ dédié — on les met dans
> `traits` en l'indiquant dans le nom (ex. `"Embrasement (action légendaire)"`).

---

## 5. `proficiencyBonus` par facteur de puissance

| FP | Bonus | | FP | Bonus |
|---|---|---|---|---|
| 0–4 | +2 | | 17–20 | +6 |
| 5–8 | +3 | | 21–24 | +7 |
| 9–12 | +4 | | 25–28 | +8 |
| 13–16 | +5 | | 29–30 | +9 |

Rappels dérivés (jamais fournis) : `mod(carac) = (score − 10) / 2` arrondi vers le bas ;
`mod(save) = mod(carac) + proficiencyBonus` si la carac est dans `saveProficiencies`.

**Unités** : `speed`, `reach`, `range`, `area` sont des textes affichés tels quels
(les 331 blocs SRD utilisent les pieds, `"30 ft"`).

---

## 6. Exemple minimal (validé)

```json
{
  "id": "thal-loup-cendres",
  "name": "Loup des cendres",
  "size": "M",
  "type": "bête",
  "cr": 1,
  "proficiencyBonus": 2,
  "ac": 13,
  "hp": { "average": 26, "formula": "4d10+4" },
  "speed": { "walk": "40 ft" },
  "abilities": { "FOR": 14, "DEX": 15, "CON": 13, "INT": 3, "SAG": 12, "CHA": 6 },
  "saveProficiencies": [],
  "traits": [
    { "name": "Odorat aiguisé", "description": "Avantage aux tests de Sagesse (Perception) reposant sur l'odorat." }
  ],
  "attacks": [
    { "name": "Morsure", "kind": "tohit", "ability": "FOR", "addAbilityToDamage": true,
      "actionType": "action", "reach": "5 ft",
      "condition": "Prone",
      "effect": "Si la cible est de taille G ou inférieure, elle a l'état Prone.",
      "damage": [ { "dice": "2d6", "type": "piercing" } ] }
  ],
  "attackOptions": [
    { "type": "single", "attack": "Morsure" }
  ]
}
```

> Toucher dérivé : `FOR(+2) + maîtrise(+2)` = **+4**. Dégâts : `2d6 + FOR(+2)`.
> Au journal : `… = 9 dégâts → Prone`.

---

## 7. Exemple complet (validé)

Couvre : multiattaque, attaque à sauvegarde de zone (régie `CON`, save cible `DEX`),
attaque à sauvegarde infligeant un état (régie `CHA`), état infligé au toucher,
résistances/immunités, traits (dont action légendaire en texte), allonge > une case.

```json
{
  "id": "thal-archonte-cendres",
  "name": "Archonte de cendres",
  "size": "G",
  "type": "élémentaire",
  "cr": 8,
  "proficiencyBonus": 3,
  "ac": 16,
  "hp": { "average": 110, "formula": "13d10+39" },
  "speed": { "walk": "30 ft", "fly": "60 ft" },
  "abilities": { "FOR": 18, "DEX": 14, "CON": 18, "INT": 12, "SAG": 14, "CHA": 16 },
  "saveProficiencies": [ "DEX", "CON", "SAG" ],
  "damageResistances": [ "nonmagical bludgeoning, piercing, and slashing" ],
  "damageImmunities": [ "fire", "poison" ],
  "damageVulnerabilities": [ "cold" ],
  "conditionImmunities": [ "Poisoned", "Exhaustion" ],
  "traits": [
    { "name": "Corps incandescent", "description": "Une créature qui touche l'archonte au corps à corps subit 1d6 dégâts de feu." },
    { "name": "Embrasement (action légendaire)", "description": "À la fin du tour d'une autre créature, l'archonte inflige 1d6 feu à une créature à 9 m ou moins." }
  ],
  "attacks": [
    { "name": "Griffe ardente", "kind": "tohit", "ability": "FOR", "addAbilityToDamage": true,
      "actionType": "action", "reach": "10 ft",
      "condition": "Grappled",
      "effect": "Si la cible est de taille G ou inférieure, elle a l'état Grappled (DD d'évasion 15).",
      "damage": [ { "dice": "2d6", "type": "slashing" }, { "dice": "1d6", "type": "fire" } ] },
    { "name": "Souffle de cendres", "kind": "save", "ability": "CON",
      "actionType": "action", "save": { "ability": "DEX" }, "area": "cône de 9 m",
      "recharge": "5-6", "halfOnSave": true,
      "damage": [ { "dice": "6d6", "type": "fire" } ] },
    { "name": "Regard calcinant", "kind": "save", "ability": "CHA",
      "actionType": "action", "save": { "ability": "SAG" }, "range": "18 m",
      "condition": "Blinded",
      "effect": "La cible a l'état Blinded jusqu'à la fin de son prochain tour." }
  ],
  "attackOptions": [
    { "type": "multiattack", "description": "Deux griffes ardentes",
      "sequence": [ { "attack": "Griffe ardente", "count": 2 } ] },
    { "type": "single", "attack": "Souffle de cendres" },
    { "type": "single", "attack": "Regard calcinant" }
  ]
}
```

Valeurs dérivées par l'app :
- **Griffe ardente** : toucher `FOR(+4)+3` = **+7** ; dégâts `2d6 + 4` puis `1d6 fire`.
- **Souffle de cendres** : DC `8 + CON(+4) + 3` = **15** ; la cible jette `DEX` ; `6d6 fire`.
- **Regard calcinant** : DC `8 + CHA(+3) + 3` = **14** ; la cible jette `SAG` → `Blinded`.

---

## 8. Liste de contrôle que je suis pour chaque bloc

1. Les six caractéristiques sont présentes, en codes français.
2. `proficiencyBonus` cohérent avec le FP (table §5).
3. Chaque attaque a une `ability` (carac régissante) ; **aucun** `toHit` ni `save.dc` figé.
4. Dés de dégâts **sans modificateur** ; `addAbilityToDamage` posé pour les attaques d'arme.
5. Types de dégâts et états en **anglais** ; `save.ability` = sauvegarde de la cible.
6. Chaque `attackOptions[].attack` (et `sequence[].attack`) pointe vers un `name` existant.
7. Actions légendaires / réactions repliées dans `traits`, avec mention dans le nom.
