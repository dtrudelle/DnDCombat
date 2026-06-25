import Foundation
import Observation

// MARK: - Bibliothèque

@Observable
final class Library {
    var monsters: [Monster] = []

    /// IDs des monstres « maison » (dupliqués/édités), persistés à part du SRD.
    private(set) var customIDs: Set<String> = []
    private let customURL: URL?

    /// `customURL` injectable pour les tests ; sinon Application Support/DnDCombat/custom-monsters.json.
    init(customURL: URL? = nil) {
        self.customURL = customURL ?? Library.defaultCustomURL
    }

    func isCustom(_ id: Monster.ID) -> Bool { customIDs.contains(id) }

    /// Charge la bibliothèque SRD 2024 embarquée (fichier ajouté à la cible), puis les monstres maison.
    func loadBundled() {
        guard let url = Bundle.main.url(forResource: "srd-2024-monsters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Monster].self, from: data) else {
            print("⚠️ srd-2024-monsters.json introuvable — pensez à l'ajouter à la cible (Target Membership).")
            loadCustom()
            return
        }
        monsters = decoded.sorted { $0.name < $1.name }
        loadCustom()
    }

    func add(_ monster: Monster) {
        if let i = monsters.firstIndex(where: { $0.id == monster.id }) {
            monsters[i] = monster
        } else {
            monsters.append(monster)
            monsters.sort { $0.name < $1.name }
        }
    }

    // MARK: Monstres maison (duplication + persistance)

    /// Duplique n'importe quel monstre en une copie maison éditable (nouveau nom + id unique).
    func duplicate(_ source: Monster) -> Monster {
        var copy = source
        copy.name = source.name + " (copie)"
        copy.id = uniqueID(base: source.id + "-copie")
        return copy
    }

    /// Insère ou met à jour un monstre maison, puis persiste.
    func upsertCustom(_ monster: Monster) {
        customIDs.insert(monster.id)
        add(monster)
        saveCustom()
    }

    /// Supprime un monstre maison (sans effet sur le SRD).
    func deleteCustom(_ id: Monster.ID) {
        guard customIDs.contains(id) else { return }
        monsters.removeAll { $0.id == id }
        customIDs.remove(id)
        saveCustom()
    }

    private func uniqueID(base: String) -> String {
        let existing = Set(monsters.map { $0.id })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private func loadCustom() {
        guard let url = customURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Monster].self, from: data) else { return }
        for m in decoded {
            customIDs.insert(m.id)
            add(m)
        }
    }

    private func saveCustom() {
        guard let url = customURL else { return }
        let customs = monsters.filter { customIDs.contains($0.id) }
        guard let data = try? JSONEncoder().encode(customs) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static var defaultCustomURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("DnDCombat/custom-monsters.json", isDirectory: false)
    }

    func search(_ query: String) -> [Monster] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return monsters }
        return monsters.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func decode(fromJSON text: String) -> Result<Monster, Error> {
        do { return .success(try JSONDecoder().decode(Monster.self, from: Data(text.utf8))) }
        catch { return .failure(error) }
    }

    /// Décode un objet unique `{ … }` OU un tableau `[ {…}, {…} ]`.
    func decodeMany(fromJSON text: String) -> Result<[Monster], Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        do {
            if trimmed.hasPrefix("[") {
                return .success(try JSONDecoder().decode([Monster].self, from: data))
            } else {
                return .success([try JSONDecoder().decode(Monster.self, from: data)])
            }
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - État d'interface (pilote les feuilles modales depuis le menu)

@Observable
final class UIState {
    var showAddMonster = false
    var showImport = false
    var showRoster = false
    var showSave = false
    var showLoad = false
    var showLibrary = false
    var showCodex = false
    var showTreasure = false
}

// MARK: - Utilitaires partagés

func crLabel(_ cr: Double) -> String {
    switch cr {
    case 0.125: return "1/8"
    case 0.25:  return "1/4"
    case 0.5:   return "1/2"
    default:    return cr == cr.rounded() ? String(Int(cr)) : String(cr)
    }
}

/// Lignes de résistances/immunités/vulnérabilités à afficher (non vides seulement).
func resistanceLines(_ m: Monster) -> [(label: String, value: String)] {
    var out: [(String, String)] = []
    func add(_ label: String, _ arr: [String]?) {
        if let a = arr, !a.isEmpty { out.append((label, a.joined(separator: ", "))) }
    }
    add("Résistances", m.damageResistances)
    add("Immunités (dégâts)", m.damageImmunities)
    add("Vulnérabilités", m.damageVulnerabilities)
    add("Immunités (états)", m.conditionImmunities)
    return out
}

func signedString(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }
