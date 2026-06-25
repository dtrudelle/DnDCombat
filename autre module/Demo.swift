import Foundation

// Bloc d'exemple intégré (identique à monstre-format-exemple.json).
let exampleMonsterJSON = """
{
  "id": "veilleur-de-cendres",
  "name": "Veilleur de cendres",
  "size": "Grande",
  "type": "créature artificielle",
  "cr": 5,
  "proficiencyBonus": 3,
  "ac": 16,
  "hp": { "average": 95, "formula": "10d10+40" },
  "speed": { "marche": "30 ft" },
  "abilities": { "FOR": 18, "DEX": 10, "CON": 18, "INT": 6, "SAG": 12, "CHA": 8 },
  "saveProficiencies": ["CON", "SAG"],
  "damageResistances": ["contondant, perforant et tranchant des attaques non magiques"],
  "damageImmunities": ["feu", "poison"],
  "conditionImmunities": ["charmé", "empoisonné", "épuisement"],
  "traits": [
    { "name": "Esprit immuable", "description": "Avantage aux sauvegardes contre charmé, effrayé et paralysé." },
    { "name": "Corps de cendre", "description": "Quand il subit des dégâts de feu, sa prochaine attaque inflige 1d6 feu supplémentaire." }
  ],
  "attacks": [
    { "name": "Coup de cendre", "kind": "tohit", "toHit": 7, "reach": "5 ft",
      "damage": [ { "dice": "2d8+4", "type": "contondant" }, { "dice": "1d6", "type": "feu" } ] },
    { "name": "Souffle de cendres", "kind": "save", "save": { "ability": "DEX", "dc": 15 }, "area": "15-ft cone",
      "damage": [ { "dice": "7d6", "type": "feu" } ], "halfOnSave": true,
      "effect": "Sur un échec, la cible est aveuglée jusqu'à la fin de son prochain tour.", "recharge": "5-6" },
    { "name": "Regard de cendre", "kind": "save", "save": { "ability": "SAG", "dc": 15 }, "damage": [],
      "effect": "Sur un échec, la cible est paralysée jusqu'à la fin de son prochain tour." }
  ],
  "attackOptions": [
    { "type": "multiattack", "description": "Deux attaques de Coup de cendre.",
      "sequence": [ { "attack": "Coup de cendre", "count": 2 } ] },
    { "type": "single", "attack": "Souffle de cendres" },
    { "type": "single", "attack": "Regard de cendre" }
  ]
}
"""

private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

private func describe(_ outcomes: [AttackOutcome]) {
    for o in outcomes {
        switch o {
        case .hit(let atk, let dmg):
            let crit = atk.isCritical ? " CRITIQUE" : (atk.isFumble ? " (1 naturel)" : "")
            let breakdown = dmg.parts.map { "\($0.subtotal) \($0.type)" }.joined(separator: " + ")
            print("  • \(atk.attackName) : touche \(atk.total) [d20 \(atk.d20.chosen)]\(crit) → \(breakdown) = \(dmg.total) dégâts")
        case .save(let sa):
            let half = sa.halfOnSave ? ", demi si réussite" : ""
            let dmgStr = sa.damage.map { " → \($0.total) dégâts" } ?? ""
            let eff = sa.effect.map { "  | \($0)" } ?? ""
            print("  • \(sa.attackName) : DD \(sa.dc) \(sa.ability.rawValue)\(half)\(dmgStr)\(eff)")
        }
    }
}

func runDemo() {
    guard let monster = try? JSONDecoder().decode(Monster.self, from: Data(exampleMonsterJSON.utf8)) else {
        print("✗ Échec du décodage du bloc.")
        return
    }

    print("== \(monster.name) — FP \(monster.cr) ==")
    print("CA \(monster.ac) · PV \(monster.hp.average) (\(monster.hp.formula)) · Vitesse \(monster.speed["marche"] ?? "?")")
    print("Saves : " + Ability.allCases.map { "\($0.rawValue) \(signed(monster.saveModifier($0)))" }.joined(separator: "  "))

    // Seed fixe → résultats reproductibles.
    var roller = DiceRoller.seeded(7)

    print("\n[Save CON]")
    let s = roller.rollSave(.CON, for: monster)
    print("  d20 \(s.d20.chosen) \(signed(s.modifier)) = \(s.total)")

    print("\n[Bouton Attaque — option 0 = multiattaque, lancée en entier]")
    describe(roller.resolveOption(monster.attackOptions[0], for: monster))

    print("\n[Souffle de cendres — attaque à sauvegarde]")
    describe(roller.resolveOption(monster.attackOptions[1], for: monster))

    print("\n[Regard de cendre — effet sans dégât]")
    describe(roller.resolveOption(monster.attackOptions[2], for: monster))

    print("\n[Avantage / désavantage]")
    let adv = roller.d20(.advantage)
    let dis = roller.d20(.disadvantage)
    print("  avantage    : dés \(adv.dice) → \(adv.chosen)")
    print("  désavantage : dés \(dis.dice) → \(dis.chosen)")

    runChecks(monster)
}

func runChecks(_ m: Monster) {
    var passed = 0, total = 0
    func check(_ label: String, _ cond: Bool) {
        total += 1; if cond { passed += 1 }
        print("  \(cond ? "✓" : "✗") \(label)")
    }
    print("\n=== Vérifications ===")
    check("CON save = +7 (mod +4 +3 maîtrise)", m.saveModifier(.CON) == 7)
    check("SAG save = +4 (mod +1 +3 maîtrise)", m.saveModifier(.SAG) == 4)
    check("FOR save = +4 (non maîtrisé)",        m.saveModifier(.FOR) == 4)
    check("DEX save = +0",                       m.saveModifier(.DEX) == 0)
    check("INT save = −2",                       m.saveModifier(.INT) == -2)
    check("3 options d'attaque",                 m.attackOptions.count == 3)
    check("besoin d'un menu (>1 option)",        m.needsAttackPicker)
    check("Coup de cendre = 2 composantes",      m.attack(named: "Coup de cendre")?.damageComponents.count == 2)
    check("Regard = 0 dégât",                    m.attack(named: "Regard de cendre")?.damageComponents.isEmpty == true)

    if let f = DiceFormula.parse("2d8+4") { check("parse 2d8+4", f.count == 2 && f.sides == 8 && f.modifier == 4) }
    else { check("parse 2d8+4", false) }
    if let f = DiceFormula.parse("7d6")   { check("parse 7d6",   f.count == 7 && f.sides == 6 && f.modifier == 0) }
    else { check("parse 7d6", false) }
    if let f = DiceFormula.parse("1d6")   { check("parse 1d6",   f.count == 1 && f.sides == 6 && f.modifier == 0) }
    else { check("parse 1d6", false) }

    // Déterminisme : même seed ⇒ même jet.
    var r1 = DiceRoller.seeded(99)
    var r2 = DiceRoller.seeded(99)
    check("déterminisme à seed égale", r1.die(20) == r2.die(20))

    print("\n\(passed)/\(total) vérifications réussies.")
}
