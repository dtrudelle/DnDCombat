import Foundation
import Observation

// MARK: - Format d'une rencontre sauvegardée (autonome)

/// Un monstre embarqué dans une rencontre : le bloc complet + le nombre d'exemplaires.
struct SavedEntry: Codable {
    var block: Monster
    var count: Int
}

// MARK: - Ressources du système maison

/// Liste des ressources sélectionnables dans le trésor. Sert à peupler le menu déroulant.
/// La valeur stockée dans `ResourceEntry.resource` reste une simple chaîne : si la liste
/// évolue plus tard, les anciennes sauvegardes se rechargent sans casser le décodage.
enum ResourceKind: String, CaseIterable, Identifiable {
    case supplies = "Supplies"
    case fineSupplies = "Fine Supplies"
    case freshIngredientMeat = "Fresh Ingredient/Meat"
    case reagentCurative = "Reagent Curative"
    case reagentReactive = "Reagent Reactive"
    case reagentPoisonous = "Reagent Poisonous"
    case essenceArcane = "Essence Arcane"
    case essenceDivine = "Essence Divine"
    case essencePrimal = "Essence Primal"
    case branche = "Branche"
    case cuir = "Cuir"
    case cuivreFer = "Cuivre/Fer"
    case acier = "Acier"
    case clairacier = "Clairacier"
    case sombreacier = "Sombreacier"
    case glasnite = "Glasnite"
    case boisDeSombrefaille = "Bois de Sombrefaille"
    case selDeNamaris = "Sel de Namaris"
    case ambreDeSelene = "Ambre de Sélène"
    case coeurDeLune = "Cœur-de-Lune"

    var id: String { rawValue }
}

/// Cinq niveaux de rareté. Le `rawValue` (clé stable) est en anglais pour la persistance ;
/// `label` fournit l'affichage en français.
enum Rarity: String, Codable, CaseIterable, Identifiable {
    case common, uncommon, rare, veryRare, legendary

    var id: String { rawValue }
    var label: String {
        switch self {
        case .common:    return "Commun"
        case .uncommon:  return "Peu commun"
        case .rare:      return "Rare"
        case .veryRare:  return "Très rare"
        case .legendary: return "Légendaire"
        }
    }
}

/// Une ressource du butin : son nom, sa quantité et sa rareté.
struct ResourceEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var resource: String = ResourceKind.supplies.rawValue
    var count: Int = 1
    var rarity: Rarity = .common
}

/// Trésor lié à une rencontre : valeur en pièces de la campagne + butin libre + ressources.
struct Treasure: Codable, Equatable {
    var aureon: Int = 0
    var solari: Int = 0
    var scaille: Int = 0
    var notes: String = ""
    var resources: [ResourceEntry] = []

    var isEmpty: Bool {
        aureon == 0 && solari == 0 && scaille == 0 && notes.isEmpty && resources.isEmpty
    }

    init() {}

    // Décodage tolérant : chaque champ absent (anciennes sauvegardes) reprend sa valeur par défaut.
    enum CodingKeys: String, CodingKey { case aureon, solari, scaille, notes, resources }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aureon    = try c.decodeIfPresent(Int.self, forKey: .aureon) ?? 0
        solari    = try c.decodeIfPresent(Int.self, forKey: .solari) ?? 0
        scaille   = try c.decodeIfPresent(Int.self, forKey: .scaille) ?? 0
        notes     = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        resources = try c.decodeIfPresent([ResourceEntry].self, forKey: .resources) ?? []
    }
}

/// Une rencontre sur disque. Tout est embarqué : image (base64) + blocs de monstres complets.
struct EncounterFile: Codable {
    var name: String
    var gridColumns: Int
    var gridRows: Int
    var imageBase64: String?
    var entries: [SavedEntry]
    var treasure: Treasure?   // optionnel : les rencontres d'avant cette version se chargent sans trésor
}

// MARK: - Magasin de rencontres (Application Support)

@Observable
final class EncounterStore {

    /// Référence légère vers un fichier sauvegardé (pour les listes).
    struct Ref: Identifiable, Hashable {
        let id: String     // nom de fichier (unique)
        let name: String   // nom affiché
    }

    private(set) var saved: [Ref] = []
    private let dir: URL

    /// `directory` injectable pour les tests ; sinon Application Support/DnDCombat/Encounters.
    init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("DnDCombat/Encounters", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        refresh()
    }

    // Pour lister sans décoder toute l'image.
    private struct NameOnly: Codable { var name: String }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        var refs: [Ref] = []
        for url in files where url.pathExtension == "json" {
            let name = (try? JSONDecoder().decode(NameOnly.self, from: Data(contentsOf: url)))?.name
                ?? url.deletingPathExtension().lastPathComponent
            refs.append(Ref(id: url.lastPathComponent, name: name))
        }
        saved = refs.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func save(_ file: EncounterFile) throws -> Ref {
        let url = dir.appendingPathComponent("\(slugify(file.name)).json")
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomic)
        refresh()
        return Ref(id: url.lastPathComponent, name: file.name)
    }

    func load(_ ref: Ref) throws -> EncounterFile {
        let url = dir.appendingPathComponent(ref.id)
        return try JSONDecoder().decode(EncounterFile.self, from: Data(contentsOf: url))
    }

    func delete(_ ref: Ref) throws {
        try FileManager.default.removeItem(at: dir.appendingPathComponent(ref.id))
        refresh()
    }

    private func slugify(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var slug = String(String.UnicodeScalarView(
            s.lowercased().unicodeScalars.map { allowed.contains($0) ? $0 : "-" }))
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "rencontre" : slug
    }
}
