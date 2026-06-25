import Foundation

func runCombatDemo() {
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "srd-2024-monsters.json"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let monsters = try? JSONDecoder().decode([Monster].self, from: data) else {
        print("✗ Impossible de charger la bibliothèque (\(path))"); return
    }

    let goblin = monsters.first { $0.name.localizedCaseInsensitiveContains("goblin") }
        ?? monsters.first { !$0.attacks.isEmpty }!
    let aboleth = monsters.first { $0.name == "Aboleth" }!

    var passed = 0, total = 0
    func check(_ s: String, _ c: Bool) { total += 1; if c { passed += 1 }; print("  \(c ? "✓" : "✗") \(s)") }

    // Mise en place du combat
    let enc = Encounter()
    enc.roller = .seeded(20)                       // reproductible
    enc.addGroup(goblin, count: 4)
    enc.addGroup(aboleth, count: 1)
    enc.setParty([PCEntry(name: "Aragorn", initBonus: 3),
                  PCEntry(name: "Lyra", initBonus: 1)])
    enc.startCombat()

    print("=== Ordre d'initiative (Round \(enc.round)) ===")
    for e in enc.order {
        print("  \(e.id == enc.activeID ? "▶" : " ") \(e.displayName) — \(e.initiative)")
    }
    print("")

    check("round == 1", enc.round == 1)
    check("ordre = 4 lignes (2 PJ + 2 groupes)", enc.order.count == 4)
    check("ordre trié décroissant", zip(enc.order, enc.order.dropFirst()).allSatisfy { $0.initiative >= $1.initiative })
    check("actif = première ligne", enc.activeID == enc.order.first?.id)

    // Groupe : 4 instances, PV indépendants
    let goblins = enc.groups.first { $0.label == goblin.name }!
    check("4 \(goblin.name) instanciés", goblins.instances.count == 4)
    let g1 = goblins.instances[0]
    let before = g1.currentHP
    g1.applyDamage(3)
    check("dégâts appliqués", g1.currentHP == max(0, before - 3))
    g1.applyDamage(999)
    check("0 PV = hors-combat", g1.isDefeated && g1.currentHP == 0)
    check("voisin intact (PV propres)", goblins.instances[1].currentHP == goblins.instances[1].maxHP)

    // CA ajustable
    let ab = enc.groups.first { $0.label == "Aboleth" }!.instances[0]
    ab.adjustAC(by: 2)
    check("CA +2 → effectiveAC", ab.effectiveAC == ab.block.ac + 2)

    // Bouton Attaque (menu si plusieurs options) + journal
    let outcomes = enc.performAttack(on: ab)
    if outcomes.isEmpty && ab.block.needsAttackPicker {
        let multi = enc.performAttack(on: ab, optionIndex: 0)   // option 0 = multiattaque
        check("multiattaque via index → résultats", !multi.isEmpty)
    } else {
        check("attaque → résultats", !outcomes.isEmpty)
    }

    // Jet de sauvegarde
    let sr = enc.rollSave(.DEX, on: ab)
    check("save DEX = d20 + mod", sr.total == sr.d20.chosen + sr.modifier)
    check("mod = celui de la fiche", sr.modifier == ab.block.saveModifier(.DEX))

    // Tours
    let firstID = enc.order.first?.id
    for _ in enc.order { enc.nextTurn() }
    check("cycle complet → round 2", enc.round == 2)
    check("retour au premier", enc.activeID == firstID)
    enc.previousTurn()
    check("tour précédent → round 1", enc.round == 1)

    // Avantage / désavantage
    enc.advantage = true; enc.disadvantage = false
    check("avantage seul", enc.rollMode == .advantage)
    enc.disadvantage = true
    check("les deux ON = normal", enc.rollMode == .normal)

    print("\n=== Journal (5 dernières entrées) ===")
    for e in enc.log.prefix(5) { print("  • \(e.title) : \(e.detail)") }

    print("\n\(passed)/\(total) vérifications réussies.")
}
