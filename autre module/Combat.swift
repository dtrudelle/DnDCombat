import Foundation
import Observation

// MARK: - Journal des jets

struct LogEntry: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

// MARK: - Instance de monstre en combat

/// Une créature concrète sur le champ de bataille (Gobelin 1, 2, …).
/// `block` est la fiche immuable partagée ; PV courants et delta de CA lui sont propres.
@Observable
final class MonsterInstance: Identifiable {
    let id = UUID()
    let block: Monster
    var name: String
    var maxHP: Int
    var currentHP: Int
    var acAdjustment: Int = 0     // bonus/malus temporaire (clic sur la CA)

    init(block: Monster, name: String, maxHP: Int? = nil) {
        self.block = block
        self.name = name
        let hp = maxHP ?? block.hp.average
        self.maxHP = hp
        self.currentHP = hp
    }

    var effectiveAC: Int { block.ac + acAdjustment }
    var isDefeated: Bool { currentHP <= 0 }

    func applyDamage(_ amount: Int) { currentHP = max(0, currentHP - amount) }   // 0 = hors-combat
    func heal(_ amount: Int) { currentHP = min(maxHP, currentHP + amount) }
    func adjustAC(by delta: Int) { acAdjustment += delta }
}

// MARK: - Groupe de monstres (une seule ligne d'initiative)

@Observable
final class MonsterGroup: Identifiable {
    let id = UUID()
    let block: Monster
    var label: String
    var instances: [MonsterInstance]
    var initiative: Int = 0       // un seul jet pour tout le groupe

    init(block: Monster, count: Int) {
        self.block = block
        self.label = block.name
        let n = max(1, count)
        self.instances = (1...n).map {
            MonsterInstance(block: block, name: n > 1 ? "\(block.name) \($0)" : block.name)
        }
    }

    var displayName: String { instances.count > 1 ? "\(label) ×\(instances.count)" : label }
    var initiativeModifier: Int { block.abilities.modifier(.DEX) }
}

// MARK: - Personnage-joueur (roster + initiative en combat)

@Observable
final class PCEntry: Identifiable {
    let id = UUID()
    var name: String
    var initBonus: Int
    var initiative: Int = 0
    init(name: String, initBonus: Int) { self.name = name; self.initBonus = initBonus }
}

// MARK: - Ligne d'initiative (PJ ou groupe de monstres)

enum InitiativeEntry: Identifiable {
    case pc(PCEntry)
    case monsters(MonsterGroup)

    var id: UUID {
        switch self {
        case .pc(let p): return p.id
        case .monsters(let g): return g.id
        }
    }
    var initiative: Int {
        switch self {
        case .pc(let p): return p.initiative
        case .monsters(let g): return g.initiative
        }
    }
    var displayName: String {
        switch self {
        case .pc(let p): return p.name
        case .monsters(let g): return g.displayName
        }
    }
}

// MARK: - Roster permanent

@Observable
final class Roster {
    var members: [PCEntry]
    init(members: [PCEntry] = []) { self.members = members }
}

// MARK: - Combat

@Observable
final class Encounter {
    var name: String = "Sans titre"
    var groups: [MonsterGroup] = []
    var party: [PCEntry] = []
    var order: [InitiativeEntry] = []
    var round: Int = 0                 // 0 = pas encore démarré
    var activeID: UUID?
    var advantage = false
    var disadvantage = false
    var log: [LogEntry] = []

    /// Le lanceur de dés (injectable ; `.system()` en prod, `.seeded(_)` en test).
    var roller: DiceRoller = .system()

    /// Avantage + désavantage en même temps = jet normal (règle 5e).
    var rollMode: Advantage {
        if advantage && disadvantage { return .normal }
        if advantage { return .advantage }
        if disadvantage { return .disadvantage }
        return .normal
    }

    var activeEntry: InitiativeEntry? {
        guard let id = activeID else { return nil }
        return order.first { $0.id == id }
    }

    // MARK: Construction

    func addGroup(_ block: Monster, count: Int) {
        groups.append(MonsterGroup(block: block, count: count))
    }

    func setParty(_ pcs: [PCEntry]) { party = pcs }

    /// Réinitialise pour une nouvelle rencontre (menu « Nouvelle rencontre »).
    func newEncounter() {
        groups.removeAll(); party.removeAll(); order.removeAll()
        round = 0; activeID = nil; advantage = false; disadvantage = false
        log.removeAll()
    }

    // MARK: Lancement et tours

    /// Lance l'initiative de tout le monde (PJ + monstres), trie, démarre le round 1.
    func startCombat() {
        for pc in party {
            pc.initiative = roller.d20(.normal).chosen + pc.initBonus   // l'init n'est pas affectée par les switches
        }
        for g in groups {
            g.initiative = roller.d20(.normal).chosen + g.initiativeModifier
        }
        rebuildOrder()
        round = 1
        activeID = order.first?.id
        log.removeAll()
        addLog("Combat lancé", "Round 1 — \(order.count) combattants")
    }

    func rebuildOrder() {
        let entries = party.map { InitiativeEntry.pc($0) } + groups.map { InitiativeEntry.monsters($0) }
        order = entries.sorted { $0.initiative > $1.initiative }
    }

    func nextTurn() {
        guard !order.isEmpty else { return }
        guard let cur = activeID, let idx = order.firstIndex(where: { $0.id == cur }) else {
            activeID = order.first?.id; return
        }
        let next = idx + 1
        if next >= order.count {
            activeID = order.first?.id
            round += 1
            addLog("Round \(round)")
        } else {
            activeID = order[next].id
        }
    }

    func previousTurn() {
        guard !order.isEmpty else { return }
        guard let cur = activeID, let idx = order.firstIndex(where: { $0.id == cur }) else { return }
        if idx == 0 {
            if round > 1 { round -= 1; activeID = order.last?.id }   // sinon on reste au début
        } else {
            activeID = order[idx - 1].id
        }
    }

    // MARK: Jets (alimentent le journal)

    /// Jet de sauvegarde d'une instance (un des 6 boutons).
    @discardableResult
    func rollSave(_ ability: Ability, on inst: MonsterInstance) -> SaveRoll {
        let r = roller.rollSave(ability, for: inst.block, mode: rollMode)
        addLog("\(inst.name) — save \(ability.rawValue)", "d20 \(r.d20.chosen) \(signed(r.modifier)) = \(r.total)")
        return r
    }

    /// Bouton Attaque : si `optionIndex` nil et plusieurs options, l'UI doit présenter le menu.
    @discardableResult
    func performAttack(on inst: MonsterInstance, optionIndex: Int? = nil) -> [AttackOutcome] {
        let outcomes = roller.attackAction(for: inst.block, choosing: optionIndex, mode: rollMode)
        for o in outcomes { addLog("\(inst.name) — \(summary(o).0)", summary(o).1) }
        return outcomes
    }

    // MARK: Journal

    func addLog(_ title: String, _ detail: String = "") {
        log.insert(LogEntry(title: title, detail: detail), at: 0)   // plus récent en haut
    }

    private func summary(_ o: AttackOutcome) -> (String, String) {
        switch o {
        case .hit(let atk, let dmg):
            let crit = atk.isCritical ? " (critique)" : (atk.isFumble ? " (1 naturel)" : "")
            let parts = dmg.parts.map { "\($0.subtotal) \($0.type)" }.joined(separator: " + ")
            return (atk.attackName, "touche \(atk.total)\(crit) → \(parts) = \(dmg.total)")
        case .save(let sa):
            let half = sa.halfOnSave ? ", demi si réussite" : ""
            let d = sa.damage.map { " → \($0.total) dégâts" } ?? ""
            return (sa.attackName, "DD \(sa.dc) \(sa.ability.rawValue)\(half)\(d)")
        }
    }
}

private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }
