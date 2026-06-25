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
    var maxWounds: Int
    var currentWounds: Int
    var acAdjustment: Int = 0     // bonus/malus temporaire (clic sur la CA)
    var spentRecharges: Set<String> = []   // attaques à recharge dépensées (grisées jusqu'au prochain jet)

    /// Sorts à usage limité : utilisations restantes, par nom de sort.
    /// Les sorts « à volonté » (usesPerDay nil) ne sont pas suivis ici (toujours disponibles).
    var spellUses: [String: Int] = [:]

    init(block: Monster, name: String, maxHP: Int? = nil) {
        self.block = block
        self.name = name
        let hp = maxHP ?? block.hp.average
        self.maxHP = hp
        self.currentHP = hp
        let w = block.woundCount
        self.maxWounds = w
        self.currentWounds = w
        if let sc = block.spellcasting {
            for sp in sc.spells {
                if let n = sp.usesPerDay { spellUses[sp.name] = n }
            }
        }
    }

    var effectiveAC: Int { block.ac + acAdjustment }
    // Système maison : la créature reste active tant qu'il lui reste des wounds,
    // même à 0 PV. Elle ne devient inactive (auto-skip) qu'à 0 wound.
    var isDefeated: Bool { currentWounds <= 0 }

    func applyDamage(_ amount: Int) { currentHP = max(0, currentHP - amount) }    // 0 PV ≠ hors-combat
    func heal(_ amount: Int) { currentHP = min(maxHP, currentHP + amount) }
    func applyWound(_ amount: Int) { currentWounds = max(0, currentWounds - amount) }   // 0 = hors-combat
    func healWound(_ amount: Int) { currentWounds = min(maxWounds, currentWounds + amount) }
    func adjustAC(by delta: Int) { acAdjustment += delta }

    // MARK: Budget de sorts

    /// Utilisations restantes d'un sort. nil = à volonté (illimité).
    func remainingUses(of spell: String) -> Int? { spellUses[spell] }

    /// Vrai si le sort peut encore être lancé (à volonté, ou compteur > 0).
    func canCast(_ spell: String) -> Bool {
        guard let left = spellUses[spell] else { return true }   // absent du dico = à volonté
        return left > 0
    }

    /// Décrémente le compteur d'un sort limité (sans effet pour un sort à volonté).
    func consumeSpell(_ spell: String) {
        if let left = spellUses[spell] { spellUses[spell] = max(0, left - 1) }
    }
}

// MARK: - Groupe de monstres (une seule ligne d'initiative)

@Observable
final class MonsterGroup: Identifiable {
    let id = UUID()
    let block: Monster
    var label: String
    var instances: [MonsterInstance]
    var initiative: Int = 0       // un seul jet pour tout le groupe
    var lastRechargeRound: Int = 0   // round du dernier jet de recharge (évite de re-rouler sur prev/next)

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

    /// Vrai quand toutes les instances du groupe sont à 0 wound (donc hors-combat).
    var isDefeated: Bool { instances.allSatisfy { $0.isDefeated } }
}

// MARK: - Personnage-joueur (roster + initiative en combat)

@Observable
final class PCEntry: Identifiable {
    let id = UUID()
    var name: String
    var initBonus: Int
    var initiative: Int = 0
    var isDead = false        // K.O. en combat : saut automatique du tour (runtime, jamais persisté)
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

    /// Vrai si l'entrée doit être sautée automatiquement :
    /// groupe de monstres entièrement à 0 wound, ou PJ marqué K.O. par le MJ.
    var isDefeated: Bool {
        switch self {
        case .pc(let p): return p.isDead
        case .monsters(let g): return g.isDefeated
        }
    }

    /// Valeur de départage sur la DEX en cas d'égalité d'initiative.
    /// Pour un PJ, on utilise son bonus d'init (dérivé de la DEX en 5e) faute de
    /// score de DEX stocké ; pour un groupe, le vrai modificateur de DEX du bloc.
    var dexTiebreaker: Int {
        switch self {
        case .pc(let p):       return p.initBonus
        case .monsters(let g): return g.initiativeModifier
        }
    }

    /// Vrai pour un PJ : sert d'ultime départage (les PJ jouent avant les monstres).
    var isPC: Bool {
        switch self {
        case .pc:       return true
        case .monsters: return false
        }
    }

    /// Comparateur d'ordre d'initiative à trois niveaux :
    /// 1) initiative décroissante ; 2) modificateur de DEX décroissant ;
    /// 3) à égalité totale, les PJ passent avant les monstres.
    /// Renvoie `true` si `lhs` doit être joué avant `rhs`.
    static func precedes(_ lhs: InitiativeEntry, _ rhs: InitiativeEntry) -> Bool {
        if lhs.initiative != rhs.initiative {
            return lhs.initiative > rhs.initiative
        }
        if lhs.dexTiebreaker != rhs.dexTiebreaker {
            return lhs.dexTiebreaker > rhs.dexTiebreaker
        }
        if lhs.isPC != rhs.isPC {
            return lhs.isPC   // PJ (true) avant monstre (false)
        }
        return false          // ordre stable conservé entre deux entrées équivalentes
    }
}

// MARK: - Roster permanent (persistant sur disque)

/// Forme persistée d'un PJ : on ne sauvegarde que le nom et le bonus d'init
/// (l'initiative jouée est runtime et n'est pas conservée).
struct SavedPC: Codable {
    var name: String
    var initBonus: Int
}

@Observable
final class Roster {
    var members: [PCEntry]
    private let fileURL: URL?

    /// Charge le roster depuis le disque s'il existe, sinon utilise `members` (les défauts).
    /// `fileURL` injectable pour les tests ; sinon Application Support/DnDCombat/roster.json.
    init(members: [PCEntry] = [], fileURL: URL? = nil) {
        let url = fileURL ?? Roster.defaultURL
        self.fileURL = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([SavedPC].self, from: data) {
            self.members = saved.map { PCEntry(name: $0.name, initBonus: $0.initBonus) }
        } else {
            self.members = members
        }
    }

    /// Écrit le roster sur le disque (nom + bonus d'init uniquement).
    func save() {
        guard let url = fileURL else { return }
        let dto = members.map { SavedPC(name: $0.name, initBonus: $0.initBonus) }
        guard let data = try? JSONEncoder().encode(dto) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static var defaultURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("DnDCombat/roster.json", isDirectory: false)
    }
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

    // Carte
    var mapImageData: Data?
    var gridColumns: Int = 34
    var gridRows: Int = 18
    var showGrid: Bool = false   // affichage de la grille (vignette MJ + écran joueurs) — off par défaut

    // Trésor de la rencontre (pièces + butin libre)
    var treasure = Treasure()
    var showTreasureToPlayers = false   // overlay écran joueurs (transitoire, non sauvegardé)

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

    // MARK: Édition en cours de rencontre

    /// Retire un groupe entier de la rencontre (bouton poubelle). Met l'ordre à jour si le combat tourne.
    func removeGroup(_ group: MonsterGroup) {
        let wasActive = (activeID == group.id)
        let idx = order.firstIndex { $0.id == group.id }
        groups.removeAll { $0.id == group.id }
        order.removeAll { $0.id == group.id }
        if wasActive {
            // Après suppression, l'élément suivant a glissé sur `idx` ; on s'y replace (ou sur le dernier).
            if let idx, !order.isEmpty {
                activeID = order[min(idx, order.count - 1)].id
            } else {
                activeID = order.first?.id
            }
        }
    }

    /// Retire une seule créature d'un groupe ; si le groupe devient vide, on retire le groupe.
    func removeInstance(_ inst: MonsterInstance, from group: MonsterGroup) {
        group.instances.removeAll { $0.id == inst.id }
        if group.instances.isEmpty { removeGroup(group) }
    }

    /// Renfort : ajoute des créatures en cours de partie.
    /// - même bloc qu'un groupe présent → rejoint ce groupe (même ligne d'init, pas de nouveau jet) ;
    /// - bloc inédit → nouveau groupe, jet d'initiative et insertion à sa place dans l'ordre.
    /// Hors combat (round 0) on délègue à `addGroup` : l'init sera lancée au démarrage.
    func reinforce(_ block: Monster, count: Int) {
        guard round > 0 else { addGroup(block, count: count); return }
        let n = max(1, count)
        if let existing = groups.first(where: { $0.block.id == block.id }) {
            // Le groupe passe de 1 à plusieurs : on numérote aussi la créature d'origine.
            if existing.instances.count == 1, existing.instances[0].name == existing.label {
                existing.instances[0].name = "\(existing.label) 1"
            }
            let start = existing.instances.count
            for k in 1...n {
                existing.instances.append(
                    MonsterInstance(block: block, name: "\(existing.label) \(start + k)"))
            }
            addLog("Renfort", "\(n)× \(block.name) rejoint \(existing.label) (init \(existing.initiative))")
        } else {
            let g = MonsterGroup(block: block, count: n)
            g.initiative = roller.d20(.normal).chosen + g.initiativeModifier
            groups.append(g)
            // L'ordre suit le même départage que `rebuildOrder` : on insère avant la
            // 1ʳᵉ entrée que le nouveau groupe doit précéder (init, puis DEX, puis PJ).
            let newEntry = InitiativeEntry.monsters(g)
            let i = order.firstIndex { InitiativeEntry.precedes(newEntry, $0) } ?? order.count
            order.insert(newEntry, at: i)
            addLog("Renfort", "\(g.displayName) entre en combat (init \(g.initiative))")
        }
    }

    /// Réinitialise pour une nouvelle rencontre (menu « Nouvelle rencontre »).
    func newEncounter() {
        groups.removeAll(); party.removeAll(); order.removeAll()
        round = 0; activeID = nil; advantage = false; disadvantage = false
        log.removeAll()
        name = "Sans titre"
        mapImageData = nil
        gridColumns = 34; gridRows = 18
        showGrid = false
        treasure = Treasure()
        showTreasureToPlayers = false
    }

    // MARK: Sauvegarde / chargement

    /// Capture la rencontre courante dans un fichier autonome (image + blocs complets).
    func snapshot(name: String) -> EncounterFile {
        EncounterFile(
            name: name,
            gridColumns: gridColumns,
            gridRows: gridRows,
            imageBase64: mapImageData?.base64EncodedString(),
            entries: groups.map { SavedEntry(block: $0.block, count: $0.instances.count) },
            treasure: treasure.isEmpty ? nil : treasure
        )
    }

    /// Remplace la rencontre courante par une rencontre chargée (prête, non démarrée).
    func apply(_ file: EncounterFile) {
        newEncounter()
        name = file.name
        gridColumns = file.gridColumns
        gridRows = file.gridRows
        mapImageData = file.imageBase64.flatMap { Data(base64Encoded: $0) }
        treasure = file.treasure ?? Treasure()
        for e in file.entries { addGroup(e.block, count: e.count) }
    }

    // MARK: Lancement et tours

    /// Lance l'initiative de tout le monde (PJ + monstres), trie, démarre le round 1.
    func startCombat() {
        for pc in party {
            pc.isDead = false                                           // tout le monde repart en vie
            pc.initiative = roller.d20(.normal).chosen + pc.initBonus   // l'init n'est pas affectée par les switches
        }
        for g in groups {
            g.initiative = roller.d20(.normal).chosen + g.initiativeModifier
        }
        rebuildOrder()
        round = 1
        activeID = firstActiveID()
        log.removeAll()
        addLog("Combat lancé", "Round 1 — \(order.count) combattants")
    }

    func rebuildOrder() {
        let entries = party.map { InitiativeEntry.pc($0) } + groups.map { InitiativeEntry.monsters($0) }
        order = entries.sorted { InitiativeEntry.precedes($0, $1) }
    }

    /// Affecte l'entrée active et déclenche les effets de début de tour (recharges).
    private func setActive(_ id: UUID?) {
        activeID = id
        onActivate()
    }

    /// Début du tour d'un groupe de monstres : jets de recharge, une seule fois par round
    /// (un aller-retour prev/next dans le même round ne re-roule pas).
    private func onActivate() {
        guard case .monsters(let g)? = activeEntry, g.lastRechargeRound != round else { return }
        g.lastRechargeRound = round
        rollRecharges(for: g)
    }

    /// Pour chaque attaque à recharge dépensée des créatures encore en jeu : 1d6 (journalisé) ;
    /// si le résultat atteint le seuil, l'attaque redevient disponible.
    private func rollRecharges(for group: MonsterGroup) {
        for inst in group.instances where !inst.isDefeated && !inst.spentRecharges.isEmpty {
            for name in inst.spentRecharges.sorted() {
                guard let atk = inst.block.attack(named: name),
                      let threshold = atk.rechargeThreshold else {
                    inst.spentRecharges.remove(name)   // donnée incohérente : on libère par sécurité
                    continue
                }
                let roll = roller.die(6)
                let recharged = roll >= threshold
                addLog("\(inst.name) — recharge \(name)",
                       "d6 = \(roll) (besoin \(threshold)+) → \(recharged ? "rechargée" : "indisponible")")
                if recharged { inst.spentRecharges.remove(name) }
            }
        }
    }

    func nextTurn() {
        guard !order.isEmpty else { return }
        guard let cur = activeID, let idx = order.firstIndex(where: { $0.id == cur }) else {
            setActive(firstActiveID()); return
        }
        var i = idx
        for _ in 0..<order.count {
            let next = i + 1
            if next >= order.count {
                round += 1
                addLog("Round \(round)")
                i = 0
            } else {
                i = next
            }
            if !order[i].isDefeated {
                setActive(order[i].id)
                return
            }
        }
        // Tout le monde est défait : on garde l'entrée actuelle.
    }

    func previousTurn() {
        guard !order.isEmpty else { return }
        guard let cur = activeID, let idx = order.firstIndex(where: { $0.id == cur }) else { return }
        var i = idx
        for _ in 0..<order.count {
            if i == 0 {
                if round > 1 {
                    round -= 1
                    i = order.count - 1
                } else {
                    return   // déjà au tout début, on reste
                }
            } else {
                i -= 1
            }
            if !order[i].isDefeated {
                activeID = order[i].id
                return
            }
        }
    }

    /// Première entrée non défaite (ou la première tout court si toutes sont défaites).
    private func firstActiveID() -> UUID? {
        order.first { !$0.isDefeated }?.id ?? order.first?.id
    }

    // MARK: Jets (alimentent le journal)

    /// Jet libre depuis la barre de jets : l'utilisateur saisit une formule (« 1d20+3 », « 4d6+6 »).
    /// Jet brut, sans avantage/désavantage ni critique ; journalisé comme les autres.
    @discardableResult
    func rollFormula(_ raw: String) -> (rolls: [Int], total: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let f = DiceFormula.parse(trimmed) else {
            addLog("Jet libre — \(trimmed)", "Formule invalide")
            return nil
        }
        let r = roller.roll(f)
        let detail: String
        if f.count > 0 {
            let diceList = r.rolls.map(String.init).joined(separator: ", ")
            let modPart = f.modifier != 0 ? " \(signed(f.modifier))" : ""
            detail = "\(f.count)d\(f.sides) [\(diceList)]\(modPart) = \(r.total)"
        } else {
            detail = "= \(r.total)"
        }
        addLog("Jet libre — \(trimmed)", detail)
        return r
    }

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
        for o in outcomes {
            let lines = logLines(for: o, on: inst)
            addLog(lines.title, lines.detail)
        }
        // Une attaque à recharge devient indisponible jusqu'à un futur jet de recharge réussi.
        for o in outcomes {
            if let atk = inst.block.attack(named: o.attackName), atk.recharge != nil {
                inst.spentRecharges.insert(o.attackName)
            }
        }
        return outcomes
    }

    /// Lance un sort depuis le bloc de spellcasting de l'instance.
    /// Décrémente toujours le compteur (sorts limités). Ne résout un jet et n'écrit le détail
    /// dans le journal que pour les sorts mécaniques (dégâts/sauvegarde) ; les sorts utilitaires
    /// laissent seulement une trace « lance … ».
    @discardableResult
    func castSpell(named spell: String, on inst: MonsterInstance) -> AttackOutcome? {
        guard let sc = inst.block.spellcasting,
              let entry = sc.spells.first(where: { $0.name == spell }),
              inst.canCast(spell) else { return nil }
        inst.consumeSpell(spell)

        // Sort utilitaire : on gère seulement le compteur, rien dans le journal.
        guard entry.mechanical, let atkName = entry.attackName,
              let atk = inst.block.attack(named: atkName) else { return nil }

        let outcome = roller.resolve(atk, for: inst.block, mode: rollMode)
        var lines = logLines(for: outcome, on: inst)
        if let left = inst.remainingUses(of: spell) { lines.detail += "\n(\(left) rest.)" }
        addLog(lines.title, lines.detail)
        return outcome
    }

    // MARK: Journal

    func addLog(_ title: String, _ detail: String = "") {
        log.insert(LogEntry(title: title, detail: detail), at: 0)   // plus récent en haut
    }

    /// Deux lignes pour le journal : titre (qui attaque / quoi / portée) + détail (toucher puis dégâts).
    private func logLines(for o: AttackOutcome, on inst: MonsterInstance) -> (title: String, detail: String) {
        switch o {
        case .hit(let atk, let dmg):
            let dist = distanceLabel(inst.block.attack(named: atk.attackName))
            let title = "\(inst.name) — \(atk.attackName)" + (dist.map { " — \($0)" } ?? "")
            let crit = atk.isCritical ? "  (critique)" : (atk.isFumble ? "  (1 naturel)" : "")
            let parts = dmg.parts.map { "\($0.subtotal) \($0.type)" }.joined(separator: " + ")
            var detail = "Touche \(atk.total)\(crit)\n\(parts) = \(dmg.total) dégâts"
            if let a = inst.block.attack(named: atk.attackName), let cond = a.condition {
                detail += " → \(cond)"
                if let cs = a.conditionSave {
                    detail += " (DD \(inst.block.conditionSaveDC(for: a)) \(cs.saveAbility.rawValue))"
                }
            }
            return (title, detail)
        case .save(let sa):
            let dist = distanceLabel(inst.block.attack(named: sa.attackName))
            let title = "\(inst.name) — \(sa.attackName)" + (dist.map { " — \($0)" } ?? "")
            let half = sa.halfOnSave ? ", demi si réussite" : ""
            var detail = "DD \(sa.dc) \(sa.ability.rawValue)\(half)"
            if let cond = sa.condition { detail += " → \(cond)" }
            if let d = sa.damage { detail += "\n\(d.total) dégâts" }
            else if sa.condition == nil, let eff = sa.effect { detail += "\n\(eff)" }
            return (title, detail)
        }
    }

    /// Étiquette de portée si l'attaque dépasse une case (5 ft) : range, zone d'effet, ou allonge.
    private func distanceLabel(_ atk: Attack?) -> String? {
        guard let atk else { return nil }
        if let range = atk.range { return "range \(range)" }
        if let area = atk.area { return "zone \(area)" }
        if let reach = atk.reach, reach != "5 ft" { return "allonge \(reach)" }
        return nil
    }
}

private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }
