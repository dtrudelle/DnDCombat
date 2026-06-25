import Foundation
import Observation

// MARK: - Entrée de codex (lieu, objet, PNJ, etc.)

struct CodexEntry: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var category: String
    var imageBase64: String?   // image unique, encodée en base64 pour la persistance
    var publicInfo: String     // visible par les joueurs
    var gmInfo: String         // visible par le MJ uniquement

    init(id: String = UUID().uuidString,
         title: String = "Nouvelle entrée",
         category: String = "Lieux",
         imageBase64: String? = nil,
         publicInfo: String = "",
         gmInfo: String = "") {
        self.id = id
        self.title = title
        self.category = category
        self.imageBase64 = imageBase64
        self.publicInfo = publicInfo
        self.gmInfo = gmInfo
    }

    var imageData: Data? {
        guard let imageBase64 else { return nil }
        return Data(base64Encoded: imageBase64)
    }

    mutating func setImage(_ data: Data?) {
        imageBase64 = data?.base64EncodedString()
    }
}

// MARK: - Bibliothèque de codex (persistante sur disque)

@Observable
final class CodexLibrary {
    var entries: [CodexEntry] = []

    /// Catégories créées par l'utilisateur, persistées indépendamment des entrées.
    /// (Les catégories par défaut sont fournies par `defaultCategories` et ne sont
    /// donc pas dupliquées ici.)
    private(set) var customCategories: [String] = []

    private let fileURL: URL?

    /// Catégories fournies d'office par l'application.
    static let defaultCategories = [
        "Lieux", "Objets", "PNJ",
        "Village", "Ville", "Ruine",
        "Portail", "Site religieux", "Forteresse"
    ]

    /// `fileURL` injectable pour les tests ; sinon Application Support/DnDCombat/codex.json.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? CodexLibrary.defaultURL
        load()
    }

    static var defaultURL: URL? {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DnDCombat/codex.json")
    }

    /// Toutes les catégories disponibles, triées, sans doublons :
    /// catégories par défaut ∪ catégories personnalisées ∪ catégories réellement
    /// utilisées par les entrées (au cas où une entrée importée en référence une
    /// qui ne figurerait dans aucune des deux listes).
    var categories: [String] {
        let all = Set(CodexLibrary.defaultCategories)
            .union(customCategories)
            .union(entries.map(\.category))
        return all.sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    /// Ajoute une nouvelle catégorie à la liste partagée et la persiste.
    /// Sans effet si le nom est vide ou si la catégorie existe déjà
    /// (comparaison insensible à la casse).
    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = categories.contains {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !exists else { return }
        customCategories.append(trimmed)
        save()
    }

    func entries(in category: String?) -> [CodexEntry] {
        guard let category else { return entries }
        return entries.filter { $0.category == category }
    }

    func search(_ query: String, category: String?) -> [CodexEntry] {
        let base = entries(in: category)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    func upsert(_ entry: CodexEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        save()
    }

    func delete(_ id: CodexEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    // MARK: Import en bloc

    /// Importe un lot d'entrées depuis un JSON (tableau d'entrées OU objet
    /// `{ "entries": [...] }`). Import idempotent : chaque entrée importée met à
    /// jour une entrée existante si elle correspond (par `id` si fourni, sinon par
    /// titre + catégorie insensibles à la casse), sinon elle est ajoutée. Les
    /// catégories absentes sont créées. Renvoie un récapitulatif pour l'UI.
    @discardableResult
    func importEntries(from data: Data) throws -> CodexImportResult {
        let imported = try CodexLibrary.decodeImport(data)
        var result = CodexImportResult()

        for item in imported {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let category = item.category.trimmingCharacters(in: .whitespacesAndNewlines)

            // Création de catégorie si elle n'existe nulle part encore.
            let catExists = categories.contains {
                $0.localizedCaseInsensitiveCompare(category) == .orderedSame
            }
            if !catExists, !result.newCategories.contains(category) {
                customCategories.append(category)
                result.newCategories.append(category)
            }

            // Recherche d'une entrée existante à mettre à jour.
            let existing: Int?
            if let id = item.id {
                existing = entries.firstIndex { $0.id == id }
            } else {
                existing = entries.firstIndex {
                    $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame &&
                    $0.category.localizedCaseInsensitiveCompare(category) == .orderedSame
                }
            }

            if let i = existing {
                var e = entries[i]
                e.title = title
                e.category = category
                e.publicInfo = item.publicInfo
                e.gmInfo = item.gmInfo
                if let b64 = item.imageBase64 { e.imageBase64 = b64 }  // image conservée si non fournie
                entries[i] = e
                result.updated += 1
            } else {
                entries.append(CodexEntry(
                    id: item.id ?? UUID().uuidString,
                    title: title,
                    category: category,
                    imageBase64: item.imageBase64,
                    publicInfo: item.publicInfo,
                    gmInfo: item.gmInfo))
                result.added += 1
            }
        }

        entries.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        save()
        return result
    }

    /// Accepte indifféremment un tableau `[ … ]` ou un objet `{ "entries": [ … ] }`.
    private static func decodeImport(_ data: Data) throws -> [CodexImportEntry] {
        let dec = JSONDecoder()
        if let arr = try? dec.decode([CodexImportEntry].self, from: data) {
            return arr
        }
        return try dec.decode(CodexImportFile.self, from: data).entries
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }

        // Nouveau format : objet { entries, categories }.
        if let file = try? JSONDecoder().decode(CodexFile.self, from: data) {
            entries = file.entries.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            customCategories = file.categories
            return
        }

        // Ancien format : tableau d'entrées seul. On migre en conservant les entrées.
        if let legacy = try? JSONDecoder().decode([CodexEntry].self, from: data) {
            entries = legacy.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            customCategories = []
        }
    }

    func save() {
        guard let fileURL else { return }
        let file = CodexFile(entries: entries, categories: customCategories)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Format de sérialisation du codex sur disque.
/// Décodage tolérant aux clés manquantes pour rester robuste aux fichiers partiels.
private struct CodexFile: Codable {
    var entries: [CodexEntry]
    var categories: [String]

    init(entries: [CodexEntry], categories: [String]) {
        self.entries = entries
        self.categories = categories
    }

    enum CodingKeys: String, CodingKey { case entries, categories }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([CodexEntry].self, forKey: .entries) ?? []
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
    }
}

// MARK: - Format d'import en bloc

/// Récapitulatif renvoyé après un import (pour l'affichage du retour à l'UI).
struct CodexImportResult {
    var added = 0
    var updated = 0
    var newCategories: [String] = []
}

/// Entrée telle qu'elle peut être rédigée à la main dans un fichier d'import.
/// Seul `title` est réellement utile ; tout le reste a une valeur par défaut.
/// Décodage tolérant (`decodeIfPresent`) : une clé absente n'échoue jamais.
struct CodexImportEntry: Decodable {
    var id: String?            // optionnel : généré si absent
    var title: String
    var category: String
    var publicInfo: String
    var gmInfo: String
    var imageBase64: String?   // base64 brut, sans préfixe « data: »

    enum CodingKeys: String, CodingKey {
        case id, title, category, publicInfo, gmInfo, imageBase64
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(String.self, forKey: .id)
        title       = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        category    = try c.decodeIfPresent(String.self, forKey: .category) ?? "Lieux"
        publicInfo  = try c.decodeIfPresent(String.self, forKey: .publicInfo) ?? ""
        gmInfo      = try c.decodeIfPresent(String.self, forKey: .gmInfo) ?? ""
        imageBase64 = try c.decodeIfPresent(String.self, forKey: .imageBase64)
    }
}

/// Variante objet du fichier d'import : `{ "entries": [ … ] }`.
private struct CodexImportFile: Decodable {
    var entries: [CodexImportEntry]

    enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([CodexImportEntry].self, forKey: .entries) ?? []
    }
}

// MARK: - État d'affichage côté joueurs

/// Référence l'entrée actuellement poussée à l'écran joueur (par id), ou nil.
/// Le push est toujours lié à la sélection MJ courante : changer de sélection
/// ou fermer le codex retire automatiquement l'affichage joueur.
@Observable
final class CodexDisplayState {
    var pushedID: CodexEntry.ID? = nil

    func push(_ id: CodexEntry.ID) { pushedID = id }
    func clear() { pushedID = nil }
    func toggle(_ id: CodexEntry.ID) {
        pushedID = (pushedID == id) ? nil : id
    }
    func isPushed(_ id: CodexEntry.ID) -> Bool { pushedID == id }
}
