import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Fenêtre / feuille Codex (MJ)

struct CodexSheet: View {
    @Environment(CodexLibrary.self) private var codex
    @Environment(CodexDisplayState.self) private var display
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedID: CodexEntry.ID?
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            editorColumn
                .frame(minWidth: 380)
        }
        .frame(width: 820, height: 560)
        // Fermer le codex retire l'affichage joueur.
        .onDisappear { display.clear() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    display.clear()
                    dismiss()
                }
            }
        }
    }

    // MARK: Colonne liste

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Codex").font(.headline)
                Spacer()
                Button {
                    showImporter = true
                } label: { Image(systemName: "square.and.arrow.down") }
                .help("Importer des entrées (JSON)")
                Button {
                    let new = CodexEntry()
                    codex.upsert(new)
                    selectedID = new.id
                } label: { Image(systemName: "plus") }
                .help("Nouvelle entrée")
            }
            .padding([.horizontal, .top], 10)

            TextField("Rechercher…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.top, 6)

            categoryPicker
                .padding(.horizontal, 10)
                .padding(.top, 6)

            List(selection: $selectedID) {
                ForEach(filteredEntries) { entry in
                    row(entry).tag(entry.id)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    guard let id = selectedID else { return }
                    if display.isPushed(id) { display.clear() }
                    codex.delete(id)
                    selectedID = nil
                } label: { Label("Supprimer", systemImage: "trash") }
                .disabled(selectedID == nil)
            }
            .padding(8)
        }
        // Changer de sélection retire l'affichage joueur (sauf si on re-sélectionne la même entrée).
        .onChange(of: selectedID) { oldValue, newValue in
            if let oldValue, display.isPushed(oldValue), oldValue != newValue {
                display.clear()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let res = try codex.importEntries(from: data)
                var parts: [String] = []
                if res.added > 0   { parts.append("\(res.added) ajoutée(s)") }
                if res.updated > 0 { parts.append("\(res.updated) mise(s) à jour") }
                if parts.isEmpty   { parts.append("aucune entrée valide") }
                var msg = "Import terminé : " + parts.joined(separator: ", ") + "."
                if !res.newCategories.isEmpty {
                    msg += "\nNouvelles catégories : " + res.newCategories.joined(separator: ", ") + "."
                }
                importMessage = msg
            } catch {
                importMessage = "Échec de l'import : \(error.localizedDescription)"
            }
        }
        .alert("Import du codex",
               isPresented: Binding(get: { importMessage != nil },
                                    set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var filteredEntries: [CodexEntry] {
        codex.search(query, category: selectedCategory)
    }

    /// Ligne typée explicitement (`entry: CodexEntry`) : évite que le vérificateur
    /// de types choisisse la surcharge `ForEach(Binding<C>)`.
    @ViewBuilder
    private func row(_ entry: CodexEntry) -> some View {
        HStack {
            Text(entry.title)
            Spacer()
            Text(entry.category)
                .font(.caption).foregroundStyle(.secondary)
            if display.isPushed(entry.id) {
                Image(systemName: "tv.fill").foregroundStyle(.tint)
            }
        }
    }

    private var categoryPicker: some View {
        Picker("Catégorie", selection: $selectedCategory) {
            Text("Toutes").tag(String?.none)
            ForEach(codex.categories, id: \.self) { cat in
                Text(cat).tag(String?.some(cat))
            }
        }
        .labelsHidden()
    }

    // MARK: Colonne éditeur

    private var editorColumn: some View {
        Group {
            if let selectedID, codex.entries.contains(where: { $0.id == selectedID }) {
                CodexEntryEditor(entry: binding(for: selectedID),
                                  isPushed: display.isPushed(selectedID),
                                  onToggle: {
                                      display.toggle(selectedID)
                                      if display.pushedID != nil { enc.showTreasureToPlayers = false }
                                  },
                                  onSave: { codex.save() })
            } else {
                VStack {
                    Spacer()
                    Text("Sélectionnez ou créez une entrée.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Binding construit à la main vers l'entrée d'`id` donné dans la bibliothèque.
    /// Évite les limites du subscript par index sur un `Binding` de tableau.
    private func binding(for id: CodexEntry.ID) -> Binding<CodexEntry> {
        Binding(
            get: { codex.entries.first(where: { $0.id == id }) ?? CodexEntry() },
            set: { newValue in
                if let i = codex.entries.firstIndex(where: { $0.id == id }) {
                    codex.entries[i] = newValue
                }
            }
        )
    }
}

// MARK: - Éditeur d'entrée

private struct CodexEntryEditor: View {
    @Environment(CodexLibrary.self) private var codex
    @Binding var entry: CodexEntry
    var isPushed: Bool
    var onToggle: () -> Void
    var onSave: () -> Void

    @State private var showImageImporter = false
    @State private var customCategory = ""
    @State private var showCustomCategory = false

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $entry.title)
                    .onChange(of: entry.title) { _, _ in onSave() }

                categoryField

                imageField
            }

            Section("Informations publiques (visibles des joueurs)") {
                TextEditor(text: $entry.publicInfo)
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    .onChange(of: entry.publicInfo) { _, _ in onSave() }
            }

            Section("Informations MJ") {
                TextEditor(text: $entry.gmInfo)
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    .onChange(of: entry.gmInfo) { _, _ in onSave() }
            }

            Section {
                Button {
                    onToggle()
                } label: {
                    Label(isPushed ? "Retirer de l'écran joueur" : "Afficher aux joueurs",
                          systemImage: isPushed ? "tv.slash" : "tv")
                }
                .buttonStyle(.borderedProminent)
                .tint(isPushed ? .red : .accentColor)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    entry.setImage(data)
                    onSave()
                }
            }
        }
    }

    private var categoryField: some View {
        HStack {
            Picker("Catégorie", selection: $entry.category) {
                ForEach(allCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .onChange(of: entry.category) { _, _ in onSave() }

            Button {
                showCustomCategory = true
            } label: { Image(systemName: "plus.circle") }
            .help("Nouvelle catégorie")
            .popover(isPresented: $showCustomCategory) {
                HStack {
                    TextField("Nouvelle catégorie", text: $customCategory)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { commitNewCategory() }
                    Button("OK") { commitNewCategory() }
                }
                .padding()
            }
        }
    }

    /// Catégories proposées dans le menu : la liste partagée du codex, en
    /// garantissant que la catégorie de l'entrée courante y figure (sinon le
    /// Picker n'aurait aucune sélection valide à afficher).
    private var allCategories: [String] {
        var cats = codex.categories
        if !cats.contains(entry.category) {
            cats.append(entry.category)
            cats.sort { $0.localizedCompare($1) == .orderedAscending }
        }
        return cats
    }

    /// Valide la saisie d'une nouvelle catégorie : l'ajoute à la liste partagée
    /// persistante puis l'affecte à l'entrée courante.
    private func commitNewCategory() {
        let trimmed = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            codex.addCategory(trimmed)   // liste partagée + persistance
            entry.category = trimmed     // affectation à l'entrée courante
            onSave()
        }
        customCategory = ""
        showCustomCategory = false
    }

    private var imageField: some View {
        HStack(spacing: 12) {
            Group {
                if let data = entry.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button("Choisir une image…") { showImageImporter = true }
            if entry.imageBase64 != nil {
                Button("Retirer") {
                    entry.setImage(nil)
                    onSave()
                }
            }
            Spacer()
        }
    }
}

// MARK: - Overlay côté joueur

/// Affichée par-dessus la carte/initiative quand `CodexDisplayState.pushedID` est défini.
struct CodexOverlayView: View {
    let entry: CodexEntry

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                content
                Spacer()
            }
            Spacer()
        }
        .background(Color.black.opacity(0.55))
        .transition(.opacity)
    }

    private var content: some View {
        VStack(spacing: 16) {
            if let data = entry.imageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 640, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(entry.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            if !entry.publicInfo.isEmpty {
                Text(entry.publicInfo)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .shadow(radius: 20)
        )
        .padding(40)
    }
}
