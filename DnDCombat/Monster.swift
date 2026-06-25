import Foundation

// MARK: - Caractéristiques

/// Les six caractéristiques (codes français, comme dans le format JSON).
enum Ability: String, Codable, CaseIterable {
    case FOR, DEX, CON, INT, SAG, CHA
}

/// Scores des six caractéristiques + dérivation des modificateurs.
struct AbilityScores: Codable {
    var FOR: Int
    var DEX: Int
    var CON: Int
    var INT: Int
    var SAG: Int
    var CHA: Int

    func score(_ a: Ability) -> Int {
        switch a {
        case .FOR: return FOR
        case .DEX: return DEX
        case .CON: return CON
        case .INT: return INT
        case .SAG: return SAG
        case .CHA: return CHA
        }
    }

    /// Modificateur D&D 5e : (score − 10) / 2, arrondi vers le bas.
    func modifier(_ a: Ability) -> Int {
        Int(floor(Double(score(a) - 10) / 2.0))
    }
}

// MARK: - Briques du bloc

struct HP: Codable {
    var average: Int
    var formula: String
}

struct Trait: Codable {
    var name: String
    var description: String
}

struct DamageComponent: Codable {
    var dice: String   // ex. "2d8+4"
    var type: String   // ex. "contondant"
}

struct SaveSpec: Codable {
    var ability: Ability        // sauvegarde lancée par la cible (défenseur)
    var dc: Int? = nil          // hérité : ignoré quand l'attaque a une carac régissante (DC alors dérivé)
}

/// Jet de sauvegarde optionnel contre la condition d'une attaque au toucher.
/// `dcAbility` = carac de l'attaquant (DC = 8 + mod + maîtrise) ; `saveAbility` = jet de la cible.
struct ConditionSave: Codable {
    var dcAbility: Ability
    var saveAbility: Ability
}

enum ActionEconomy: String, Codable, CaseIterable {
    case action, bonus, reaction, legendary
}

enum AttackKind: String, Codable {
    case tohit   // jet au toucher (d20 vs CA)
    case save    // attaque à sauvegarde (la cible jette)
}

/// Une attaque. Les champs non communs aux deux types sont optionnels.
struct Attack: Codable {
    var name: String
    var kind: AttackKind
    var ability: Ability? = nil          // carac régissante : dérive le toucher (mod+maîtrise) ou le DC (8+mod+maîtrise). nil = ancien format figé.
    var addAbilityToDamage: Bool? = nil  // ajoute le mod de carac à la 1ʳᵉ composante de dégâts (armes : oui ; sorts/sauvegardes : non)
    var actionType: ActionEconomy? = nil // descriptif : action / bonus / réaction / légendaire
    var toHit: Int? = nil                // hérité : utilisé uniquement si `ability` est nil
    var reach: String? = nil
    var range: String? = nil
    var save: SaveSpec? = nil
    var area: String? = nil
    var damage: [DamageComponent]? = nil
    var halfOnSave: Bool? = nil
    var condition: String? = nil   // nom anglais court de l'état infligé (ex. "Stunned"), généralement annulé par la sauvegarde
    var conditionSave: ConditionSave? = nil  // jet de sauvegarde optionnel contre la condition (attaques au toucher)
    var effect: String? = nil      // description longue (durée, save répété, DC d'évasion…) — affichée hors du journal
    var recharge: String? = nil

    /// Composantes de dégâts (vide si l'attaque n'inflige que des effets).
    var damageComponents: [DamageComponent] { damage ?? [] }

    /// Seuil minimal de recharge lu depuis `recharge` ("5-6" → 5, "6" → 6). nil si pas de recharge.
    var rechargeThreshold: Int? {
        guard let r = recharge else { return nil }
        return Int(r.prefix { $0.isNumber })
    }

    /// Libellé court pour le bouton d'attaque : "(R5+)" pour une plage, "(R6)" pour un 6 seul.
    var rechargeLabel: String? {
        guard let t = rechargeThreshold else { return nil }
        return t >= 6 ? "(R6)" : "(R\(t)+)"
    }
}

struct MultiattackEntry: Codable {
    var attack: String   // référence au `name` d'une attaque
    var count: Int
}

enum AttackOptionType: String, Codable {
    case single
    case multiattack
}

/// Un élément du menu du bouton Attaque.
struct AttackOption: Codable {
    var type: AttackOptionType
    var attack: String? = nil              // pour `single`
    var description: String? = nil         // pour `multiattack`
    var sequence: [MultiattackEntry]? = nil

    var steps: [MultiattackEntry] { sequence ?? [] }
}

// MARK: - Spellcasting

/// Un sort de la liste d'un monstre.
/// `usesPerDay` nil = à volonté (compteur illimité).
/// `mechanical` true → résout une `Attack` (dégâts/sauvegarde) et écrit dans le journal ;
/// false → sort utilitaire : on décrémente juste le compteur, pas de jet ni de ligne détaillée.
struct SpellEntry: Codable {
    var name: String
    var usesPerDay: Int? = nil
    var mechanical: Bool = false
    var attackName: String? = nil   // référence vers une Attack du tableau `attacks` (si mécanique)
}

/// Le bloc « Spellcasting » d'un monstre : carac de lancement, DD/bonus communs à tous ses sorts,
/// et la liste des sorts disponibles (avec leur budget d'utilisation).
struct SpellcastingBlock: Codable {
    var ability: Ability            // carac de lancement (affichage)
    var dc: Int                     // DD de sauvegarde commun (affichage)
    var attackBonus: Int? = nil     // bonus « +N to hit with spell attacks » s'il existe
    var spells: [SpellEntry]
}

// MARK: - Monstre

struct Monster: Codable, Identifiable {
    var id: String
    var name: String
    var size: String
    var type: String
    var cr: Double                   // accepte 0.5, 0.125, etc.
    var proficiencyBonus: Int
    var ac: Int
    var hp: HP
    var speed: [String: String]
    var abilities: AbilityScores
    var saveProficiencies: [Ability]
    var damageResistances: [String]?
    var damageImmunities: [String]?
    var damageVulnerabilities: [String]?
    var conditionImmunities: [String]?
    var traits: [Trait]?
    var attacks: [Attack]
    var attackOptions: [AttackOption]
    var spellcasting: SpellcastingBlock? = nil   // liste de sorts + budget (absent si le monstre ne lance pas de sorts)
    var wounds: Int? = nil           // système maison : nombre de wounds. Absent = 1 par défaut.

    // MARK: Dérivés

    /// Nombre de wounds effectif (1 par défaut si non défini ; jamais < 1).
    var woundCount: Int { max(1, wounds ?? 1) }

    /// Modificateur d'un jet de sauvegarde = mod. de carac (+ maîtrise si la save est maîtrisée).
    func saveModifier(_ a: Ability) -> Int {
        abilities.modifier(a) + (saveProficiencies.contains(a) ? proficiencyBonus : 0)
    }

    // MARK: Dérivation des attaques (toucher / DC / bonus de dégâts)

    /// Modificateur de la carac régissante de l'attaque (nil si non défini).
    func abilityModifier(for attack: Attack) -> Int? {
        attack.ability.map { abilities.modifier($0) }
    }

    /// Bonus au toucher dérivé = mod(carac régissante) + maîtrise. Repli sur `toHit` figé si pas de carac.
    func derivedToHit(for attack: Attack) -> Int {
        if let a = attack.ability { return abilities.modifier(a) + proficiencyBonus }
        return attack.toHit ?? 0
    }

    /// DC dérivé = 8 + mod(carac régissante) + maîtrise. Repli sur `save.dc` figé si pas de carac.
    func derivedSaveDC(for attack: Attack) -> Int {
        if let a = attack.ability { return 8 + abilities.modifier(a) + proficiencyBonus }
        return attack.save?.dc ?? 0
    }

    /// Bonus ajouté à la 1ʳᵉ composante de dégâts (0 si la case n'est pas cochée).
    func damageBonus(for attack: Attack) -> Int {
        guard attack.addAbilityToDamage == true, let a = attack.ability else { return 0 }
        return abilities.modifier(a)
    }

    /// DC dérivé du jet de sauvegarde contre la condition (8 + mod(dcAbility) + maîtrise).
    func conditionSaveDC(for attack: Attack) -> Int {
        guard let cs = attack.conditionSave else { return 0 }
        return 8 + abilities.modifier(cs.dcAbility) + proficiencyBonus
    }

    /// Retrouve une attaque par son nom (utilisé par les options/multiattaques).
    func attack(named name: String) -> Attack? {
        attacks.first { $0.name == name }
    }

    /// Le bouton Attaque ouvre un menu seulement s'il y a plus d'une option.
    var needsAttackPicker: Bool { attackOptions.count > 1 }
}
