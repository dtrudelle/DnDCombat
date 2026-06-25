import Foundation

// MARK: - Mode de jet

enum Advantage: Equatable {
    case normal, advantage, disadvantage
}

// MARK: - Générateurs

/// SplitMix64 — reproductible à seed fixe (tests).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// RNG effaçable : encapsule n'importe quelle source dans une référence,
/// pour que `DiceRoller` reste non-générique et stockable dans l'Encounter.
final class AnyRandomNumberGenerator: RandomNumberGenerator {
    private let _next: () -> UInt64
    init(_ next: @escaping () -> UInt64) { _next = next }
    func next() -> UInt64 { _next() }
}

// MARK: - Analyse d'une formule de dés ("XdY+Z")

struct DiceFormula {
    var count: Int       // nombre de dés (0 = valeur fixe)
    var sides: Int
    var modifier: Int

    static func parse(_ raw: String) -> DiceFormula? {
        let s = raw.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        var dicePart = s
        var modifier = 0
        if let signIdx = s.lastIndex(where: { $0 == "+" || $0 == "-" }), signIdx != s.startIndex {
            dicePart = String(s[s.startIndex..<signIdx])
            modifier = Int(s[signIdx...]) ?? 0
        }
        if let dIdx = dicePart.firstIndex(of: "d") {
            let countStr = dicePart[dicePart.startIndex..<dIdx]
            let sidesStr = dicePart[dicePart.index(after: dIdx)...]
            let count = countStr.isEmpty ? 1 : (Int(countStr) ?? 1)
            guard let sides = Int(sidesStr) else { return nil }
            return DiceFormula(count: count, sides: sides, modifier: modifier)
        } else {
            guard let flat = Int(dicePart) else { return nil }
            return DiceFormula(count: 0, sides: 0, modifier: flat)
        }
    }
}

// MARK: - Résultats

struct D20Roll {
    var dice: [Int]
    var mode: Advantage
    var chosen: Int
}

struct AttackRoll {
    var attackName: String
    var d20: D20Roll
    var toHit: Int
    var isCritical: Bool // 20 naturel
    var isFumble: Bool   // 1 naturel
    var total: Int { d20.chosen + toHit }
}

struct DamageRoll {
    struct Part {
        var type: String
        var rolls: [Int]
        var modifier: Int
        var subtotal: Int { rolls.reduce(0, +) + modifier }
    }
    var parts: [Part]
    var doubled: Bool
    var total: Int { parts.reduce(0) { $0 + $1.subtotal } }
}

/// Attaque à sauvegarde : l'app lance les dégâts et fournit le DD ; les cibles jettent.
struct SaveAttack {
    var attackName: String
    var ability: Ability
    var dc: Int
    var damage: DamageRoll?
    var halfOnSave: Bool
    var condition: String?
    var effect: String?
}

/// Jet de sauvegarde DU monstre (les 6 boutons).
struct SaveRoll {
    var ability: Ability
    var d20: D20Roll
    var modifier: Int
    var total: Int { d20.chosen + modifier }
}

enum AttackOutcome {
    case hit(AttackRoll, DamageRoll)
    case save(SaveAttack)

    /// Nom de l'attaque, quel que soit le type de résultat (sert au suivi des recharges).
    var attackName: String {
        switch self {
        case .hit(let a, _): return a.attackName
        case .save(let s):   return s.attackName
        }
    }
}

// MARK: - Lanceur

struct DiceRoller {
    var rng: AnyRandomNumberGenerator
    init(rng: AnyRandomNumberGenerator) { self.rng = rng }

    /// Production : source aléatoire système.
    static func system() -> DiceRoller {
        DiceRoller(rng: AnyRandomNumberGenerator {
            var g = SystemRandomNumberGenerator()
            return g.next()
        })
    }

    /// Tests : suite reproductible.
    static func seeded(_ seed: UInt64) -> DiceRoller {
        var g = SeededGenerator(seed: seed)
        return DiceRoller(rng: AnyRandomNumberGenerator { g.next() })
    }

    mutating func die(_ sides: Int) -> Int {
        sides > 0 ? Int.random(in: 1...sides, using: &rng) : 0
    }

    mutating func roll(_ f: DiceFormula, crit: Bool = false) -> (rolls: [Int], total: Int) {
        var rolls: [Int] = []
        rolls.reserveCapacity(f.count)
        // Critique « maison » : chaque dé fait son maximum (au lieu de doubler le nombre de dés).
        for _ in 0..<f.count { rolls.append(crit ? f.sides : die(f.sides)) }
        return (rolls, rolls.reduce(0, +) + f.modifier)
    }

    mutating func d20(_ mode: Advantage) -> D20Roll {
        switch mode {
        case .normal:
            let r = die(20)
            return D20Roll(dice: [r], mode: mode, chosen: r)
        case .advantage:
            let a = die(20), b = die(20)
            return D20Roll(dice: [a, b], mode: mode, chosen: max(a, b))
        case .disadvantage:
            let a = die(20), b = die(20)
            return D20Roll(dice: [a, b], mode: mode, chosen: min(a, b))
        }
    }
}

// MARK: - Résolution des actions d'un monstre

extension DiceRoller {

    mutating func rollDamage(_ components: [DamageComponent], crit: Bool = false, bonusOnFirst: Int = 0) -> DamageRoll {
        var parts: [DamageRoll.Part] = []
        for comp in components {
            guard let f = DiceFormula.parse(comp.dice) else { continue }
            let r = roll(f, crit: crit)
            parts.append(.init(type: comp.type, rolls: r.rolls, modifier: f.modifier))
        }
        // Le mod de carac s'ajoute une seule fois, à la 1ʳᵉ composante (jamais doublé au critique).
        if bonusOnFirst != 0, !parts.isEmpty {
            parts[0].modifier += bonusOnFirst
        }
        return DamageRoll(parts: parts, doubled: crit)
    }

    mutating func rollSave(_ ability: Ability, for monster: Monster, mode: Advantage = .normal) -> SaveRoll {
        SaveRoll(ability: ability, d20: d20(mode), modifier: monster.saveModifier(ability))
    }

    mutating func resolve(_ attack: Attack, for monster: Monster, mode: Advantage = .normal) -> AttackOutcome {
        switch attack.kind {
        case .tohit:
            let roll = d20(mode)
            let crit = roll.chosen == 20
            let atk = AttackRoll(attackName: attack.name, d20: roll,
                                 toHit: monster.derivedToHit(for: attack),
                                 isCritical: crit, isFumble: roll.chosen == 1)
            let dmg = rollDamage(attack.damageComponents, crit: crit,
                                 bonusOnFirst: monster.damageBonus(for: attack))
            return .hit(atk, dmg)
        case .save:
            let dmg = attack.damageComponents.isEmpty ? nil
                : rollDamage(attack.damageComponents, bonusOnFirst: monster.damageBonus(for: attack))
            return .save(SaveAttack(attackName: attack.name,
                                    ability: attack.save?.ability ?? .DEX,
                                    dc: monster.derivedSaveDC(for: attack),
                                    damage: dmg,
                                    halfOnSave: attack.halfOnSave ?? false,
                                    condition: attack.condition,
                                    effect: attack.effect))
        }
    }

    mutating func resolveOption(_ option: AttackOption, for monster: Monster, mode: Advantage = .normal) -> [AttackOutcome] {
        switch option.type {
        case .single:
            guard let name = option.attack, let atk = monster.attack(named: name) else { return [] }
            return [resolve(atk, for: monster, mode: mode)]
        case .multiattack:
            var outcomes: [AttackOutcome] = []
            for step in option.steps {
                guard let atk = monster.attack(named: step.attack) else { continue }
                for _ in 0..<step.count { outcomes.append(resolve(atk, for: monster, mode: mode)) }
            }
            return outcomes
        }
    }

    /// Bouton Attaque : une seule option → lancée direct ; sinon il faut un choix (`index`).
    mutating func attackAction(for monster: Monster, choosing index: Int? = nil, mode: Advantage = .normal) -> [AttackOutcome] {
        let options = monster.attackOptions
        if options.count == 1 { return resolveOption(options[0], for: monster, mode: mode) }
        guard let i = index, options.indices.contains(i) else { return [] }
        return resolveOption(options[i], for: monster, mode: mode)
    }
}
