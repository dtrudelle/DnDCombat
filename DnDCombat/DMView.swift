import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DMView: View {
    @Environment(Encounter.self) private var encounter
    @Environment(Library.self) private var library
    @Environment(Roster.self) private var roster
    @Environment(UIState.self) private var ui
    @Environment(WorldMapDisplayState.self) private var worldMap
    @Environment(CodexDisplayState.self) private var codexDisplay
    @Environment(\.openWindow) private var openWindow

    @State private var showMapImporter = false
    @State private var isMapTargeted = false

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                logColumn
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                monstersColumn
                    .frame(minWidth: 380)
                mapInitiativeColumn
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
            }
        }
        .frame(minWidth: 1040, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "players") } label: {
                    Label("Écran joueurs", systemImage: "rectangle.on.rectangle")
                }
            }
        }
        .sheet(isPresented: $ui.showAddMonster) { AddMonsterSheet() }
        .sheet(isPresented: $ui.showImport) { ImportMonsterSheet() }
        .sheet(isPresented: $ui.showLibrary) { MonsterLibrarySheet() }
        .sheet(isPresented: $ui.showRoster) { RosterSheet() }
        .sheet(isPresented: $ui.showSave) { SaveEncounterSheet() }
        .sheet(isPresented: $ui.showLoad) { LoadEncounterSheet() }
        .sheet(isPresented: $ui.showCodex) { CodexSheet() }
        .sheet(isPresented: $ui.showTreasure) { TreasureSheet() }
        .fileImporter(isPresented: $showMapImporter,
                      allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    encounter.mapImageData = data
                }
            }
        }
    }

    // MARK: Barre du haut (modificateurs de jet)

    private var topBar: some View {
        HStack(spacing: 12) {
            AdvantageToggles()
            DiceRollerButton()
            Spacer()
            Text("Affichage joueur : 34 × 18 cases")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    // MARK: Contrôles de tour (sous la carte, avec l'initiative)

    private var turnControls: some View {
        HStack(spacing: 8) {
            if encounter.round == 0 {
                Button {
                    encounter.setParty(roster.members)
                    encounter.startCombat()
                } label: {
                    Label("Lancer le combat", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(encounter.groups.isEmpty && roster.members.isEmpty)
                Spacer()
            } else {
                Button { encounter.previousTurn() } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Tour précédent")
                Text("Round \(encounter.round)")
                    .font(.headline).monospacedDigit()
                Button { encounter.nextTurn() } label: {
                    Label("Suivant", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Spacer()
                Button(role: .destructive) { encounter.newEncounter() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Réinitialiser le combat")
            }
        }
    }

    // MARK: Colonne gauche (journal + boutons)

    private var logColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Journal des jets").font(.headline).padding(8)
            List(encounter.log) { e in
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(.title3.weight(.semibold))
                    if !e.detail.isEmpty {
                        Text(e.detail).font(.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            Divider()
            HStack {
                Button { ui.showAddMonster = true } label: { Label("Monstre", systemImage: "plus") }
                Button { ui.showLibrary = true } label: { Label("Bibliothèque", systemImage: "books.vertical") }
                Button { ui.showCodex = true } label: { Label("Codex", systemImage: "text.book.closed") }
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    // MARK: Colonne centrale (monstres)

    private var monstersColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Monstres en combat").font(.headline).padding(8)
            ScrollView {
                VStack(spacing: 10) {
                    if encounter.groups.isEmpty {
                        Text("Aucun monstre. Utilisez « + Monstre » ou « Importer ».")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    ForEach(encounter.groups) { group in
                        GroupPanel(group: group)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: Drag & drop de la carte

    /// Charge une carte déposée sur la vignette : fichier image (Finder) ou image brute
    /// (navigateur, Aperçu…). On valide que les données forment bien une image.
    private func handleMapDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // a) Fichier glissé depuis le Finder → on lit les octets du fichier.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let url else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                    DispatchQueue.main.async { encounter.mapImageData = data }
                }
            }
            return true
        }

        // b) Image brute (sans fichier sous-jacent) → on la ré-encode en PNG.
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let img = obj as? NSImage,
                      let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                DispatchQueue.main.async { encounter.mapImageData = png }
            }
            return true
        }
        return false
    }

    // MARK: Bouton carte du monde (affichage écran joueurs)

    /// Bascule la carte de Tilea sur l'écran joueurs. Même logique que le push codex :
    /// un clic l'affiche, un autre la retire. Allume aussi l'exclusivité avec le codex.
    private var worldMapButton: some View {
        Button {
            if !worldMap.visible {   // une seule chose à l'écran joueurs
                codexDisplay.clear()
                encounter.showTreasureToPlayers = false
            }
            worldMap.toggle()
        } label: {
            Label(worldMap.visible ? "Retirer la carte des joueurs" : "Carte du monde aux joueurs",
                  systemImage: worldMap.visible ? "globe.europe.africa.fill" : "globe.europe.africa")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(worldMap.visible ? .red : .accentColor)
    }

    // MARK: Colonne droite (carte + contrôles de tour + initiative)

    private var mapInitiativeColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            worldMapButton
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Carte").font(.headline)
                    Spacer()
                    Button { showMapImporter = true } label: {
                        Label("Choisir…", systemImage: "photo")
                    }
                    .controlSize(.small)
                    if encounter.mapImageData != nil {
                        Button(role: .destructive) { encounter.mapImageData = nil } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .help("Retirer la carte")
                    }
                }
                BattlemapView(imageData: encounter.mapImageData,
                              columns: encounter.gridColumns,
                              rows: encounter.gridRows,
                              showGrid: encounter.showGrid,
                              gridColor: .white.opacity(0.30))
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: isMapTargeted ? 3 : 0)
                        if encounter.mapImageData == nil {
                            Text("Glissez une image ici")
                                .font(.caption).foregroundStyle(.white.opacity(0.45))
                                .offset(y: 22)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [.fileURL, .image], isTargeted: $isMapTargeted) { providers in
                        handleMapDrop(providers)
                    }
                HStack {
                    Toggle("Afficher la grille", isOn: Binding(
                        get: { encounter.showGrid },
                        set: { encounter.showGrid = $0 }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    TreasureButton()
                }
            }
            Divider()
            turnControls
            Divider()
            Text("Initiative").font(.headline)
            if encounter.order.isEmpty {
                Text("Lancez le combat pour établir l'ordre.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(encounter.order) { entry in
                        InitiativeRow(entry: entry)
                            .listRowBackground(entry.id == encounter.activeID
                                               ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
            }
        }
        .padding(8)
    }
}

// MARK: - Sous-vues

private struct AdvantageToggles: View {
    @Environment(Encounter.self) private var enc
    var body: some View {
        @Bindable var enc = enc
        HStack(spacing: 16) {
            Toggle("Avantage", isOn: $enc.advantage)
            Toggle("Désavantage", isOn: $enc.disadvantage)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// Ouvre la fenêtre Trésor (feuille modale, comme la Bibliothèque ou le Codex).
private struct TreasureButton: View {
    @Environment(UIState.self) private var ui
    var body: some View {
        Button { ui.showTreasure = true } label: {
            Label("Trésor", systemImage: "bag")
        }
        .controlSize(.small)
    }
}

/// Jet de dés libre : on saisit une formule (« 1d20+3 », « 4d6+6 ») et le résultat part au journal.
private struct DiceRollerButton: View {
    @Environment(Encounter.self) private var enc
    @State private var showPopover = false
    @State private var formula = ""
    @State private var lastResult: String?

    var body: some View {
        Button { showPopover = true } label: {
            Label("Dés", systemImage: "dice")
        }
        .controlSize(.small)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Jet de dés libre").font(.headline)
                HStack(spacing: 8) {
                    TextField("ex : 1d20+3 ou 4d6+6", text: $formula)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .onSubmit(roll)
                    Button("Lancer", action: roll)
                        .buttonStyle(.borderedProminent)
                        .disabled(formula.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let lastResult {
                    Text(lastResult)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    private func roll() {
        let trimmed = formula.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let r = enc.rollFormula(trimmed) {
            lastResult = "Résultat : \(r.total)"
        } else {
            lastResult = "Formule invalide"
        }
    }
}

private struct InitiativeRow: View {
    let entry: InitiativeEntry
    @Environment(Encounter.self) private var enc

    var body: some View {
        HStack(spacing: 8) {
            switch entry {
            case .pc(let p):       PCInit(pc: p)
            case .monsters(let g): GroupInit(group: g)
            }
            Text(entry.displayName)
                .strikethrough(entry.isDefeated)
            Spacer()
            if case .pc(let p) = entry {
                Button { p.isDead.toggle() } label: {
                    Image(systemName: p.isDead ? "heart.slash.fill" : "person.fill")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(p.isDead ? Color.red : Color.secondary)
                .help(p.isDead ? "PJ K.O. — réintégrer au combat" : "Marquer K.O. (saut auto du tour)")
            }
        }
        .opacity(entry.isDefeated ? 0.45 : 1)
    }

    private struct PCInit: View {
        @Bindable var pc: PCEntry
        @Environment(Encounter.self) private var enc
        var body: some View {
            TextField("", value: $pc.initiative, format: .number)
                .frame(width: 36).multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onSubmit { enc.rebuildOrder() }
        }
    }
    private struct GroupInit: View {
        @Bindable var group: MonsterGroup
        @Environment(Encounter.self) private var enc
        var body: some View {
            TextField("", value: $group.initiative, format: .number)
                .frame(width: 36).multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onSubmit { enc.rebuildOrder() }
        }
    }
}
