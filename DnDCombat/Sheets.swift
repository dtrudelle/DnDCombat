import SwiftUI

// MARK: - Ajouter un monstre depuis la bibliothèque

struct AddMonsterSheet: View {
    @Environment(Library.self) private var library
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: Monster.ID?
    @State private var count = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ajouter un monstre").font(.headline)
            TextField("Rechercher…", text: $query).textFieldStyle(.roundedBorder)

            List(library.search(query), selection: $selected) { m in
                HStack {
                    Text(m.name)
                    Spacer()
                    Text("FP \(crLabel(m.cr)) · CA \(m.ac) · \(m.hp.average) PV")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .tag(m.id)
                .onTapGesture(count: 2) {
                    enc.reinforce(m, count: count)
                    dismiss()
                }
            }
            .frame(minHeight: 280)

            HStack {
                Stepper("Quantité : \(count)", value: $count, in: 1...20).fixedSize()
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Ajouter") {
                    if let id = selected, let m = library.monsters.first(where: { $0.id == id }) {
                        enc.reinforce(m, count: count)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding()
        .frame(width: 480, height: 440)
    }
}

// MARK: - Importer un bloc JSON

struct ImportMonsterSheet: View {
    @Environment(Library.self) private var library
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var error: String?
    @State private var addToEncounter = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Importer des monstres (JSON)").font(.headline)
            Text("Collez un bloc { … } ou un tableau [ … ] de plusieurs blocs. Ils rejoignent la bibliothèque comme monstres « maison ».")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))

            Toggle("Ajouter les monstres importés à la rencontre", isOn: $addToEncounter)

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Importer") {
                    switch library.decodeMany(fromJSON: text) {
                    case .success(let monsters):
                        for m in monsters {
                            library.upsertCustom(m)               // importé = maison (badge + persistance)
                            if addToEncounter { enc.reinforce(m, count: 1) }
                        }
                        dismiss()
                    case .failure(let err):
                        error = "JSON invalide : \(err.localizedDescription)"
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 540, height: 470)
    }
}

// MARK: - Roster des PJ

struct RosterSheet: View {
    @Environment(Roster.self) private var roster
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var roster = roster
        VStack(alignment: .leading, spacing: 10) {
            Text("Roster des PJ").font(.headline)
            Text("L'app lance leur initiative (1d20 + bonus) au lancement du combat.")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach(roster.members) { pc in
                    PCRow(pc: pc)
                }
                .onDelete { roster.members.remove(atOffsets: $0); roster.save() }
            }
            .frame(minHeight: 240)

            HStack {
                Button {
                    roster.members.append(PCEntry(name: "Nouveau PJ", initBonus: 0))
                    roster.save()
                } label: { Label("Ajouter un PJ", systemImage: "plus") }
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 440, height: 400)
        .onDisappear { roster.save() }
    }
}

private struct PCRow: View {
    @Bindable var pc: PCEntry
    var body: some View {
        HStack {
            TextField("Nom", text: $pc.name).textFieldStyle(.roundedBorder)
            Stepper(value: $pc.initBonus, in: -5...15) {
                Text("Init \(signedString(pc.initBonus))").monospacedDigit()
            }
            .fixedSize()
        }
    }
}

// MARK: - Sauvegarder la rencontre

struct SaveEncounterSheet: View {
    @Environment(EncounterStore.self) private var store
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sauvegarder la rencontre").font(.headline)
            Text("La rencontre est autonome : carte et blocs de monstres complets sont embarqués.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Nom de la rencontre", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 4) {
                Label(enc.mapImageData != nil ? "Carte incluse" : "Aucune carte",
                      systemImage: enc.mapImageData != nil ? "checkmark.circle.fill" : "xmark.circle")
                Label("\(enc.groups.count) groupe(s) de monstres", systemImage: "pawprint.fill")
            }
            .font(.callout).foregroundStyle(.secondary)

            if store.saved.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                Text("Une rencontre du même nom sera remplacée.")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Sauvegarder", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 430)
        .onAppear { if enc.name != "Sans titre" { name = enc.name } }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.save(enc.snapshot(name: trimmed))
        enc.name = trimmed
        dismiss()
    }
}

// MARK: - Charger une rencontre

struct LoadEncounterSheet: View {
    @Environment(EncounterStore.self) private var store
    @Environment(Encounter.self) private var enc
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var selected: EncounterStore.Ref.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Charger une rencontre").font(.headline)

            if store.saved.isEmpty {
                Text("Aucune rencontre sauvegardée.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List(selection: $selected) {
                    ForEach(store.saved) { ref in
                        HStack {
                            Image(systemName: "map.fill").foregroundStyle(.secondary)
                            Text(ref.name)
                            Spacer()
                            Button(role: .destructive) {
                                try? store.delete(ref)
                                if selected == ref.id { selected = nil }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Effacer")
                        }
                        .tag(ref.id)
                    }
                }
                .frame(minHeight: 240)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Charger", action: load)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
            }
        }
        .padding()
        .frame(width: 440, height: 380)
        .onAppear { store.refresh() }
    }

    private func load() {
        guard let id = selected,
              let ref = store.saved.first(where: { $0.id == id }),
              let file = try? store.load(ref) else { return }
        for e in file.entries { library.add(e.block) }   // dispo dans la bibliothèque aussi
        enc.apply(file)
        dismiss()
    }
}
// MARK: - Trésor de la rencontre

/// Fenêtre Trésor (feuille modale). Pièces de la campagne, butin libre et ressources
/// du système maison. Tout est stocké sur l'Encounter et donc sauvegardé avec la rencontre.
struct TreasureSheet: View {
    @Environment(Encounter.self) private var encounter
    @Environment(CodexDisplayState.self) private var codexDisplay
    @Environment(WorldMapDisplayState.self) private var worldMap
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var enc = encounter
        VStack(alignment: .leading, spacing: 12) {
            Text("Trésor de la rencontre").font(.headline)

            // Pièces
            HStack(alignment: .bottom, spacing: 16) {
                coinField("Auréon", $enc.treasure.aureon)
                coinField("Solari", $enc.treasure.solari)
                coinField("Scaille", $enc.treasure.scaille)
                Spacer()
            }

            // Butin libre
            VStack(alignment: .leading, spacing: 4) {
                Text("Butin").font(.subheadline)
                TextEditor(text: $enc.treasure.notes)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(.secondary.opacity(0.3)))
            }

            // Ressources
            HStack {
                Text("Ressources").font(.subheadline)
                Spacer()
                Button {
                    enc.treasure.resources.append(ResourceEntry())
                } label: { Label("Ajouter une ressource", systemImage: "plus") }
                .controlSize(.small)
            }

            if enc.treasure.resources.isEmpty {
                Text("Aucune ressource. Utilisez « Ajouter une ressource ».")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
            } else {
                List {
                    ForEach($enc.treasure.resources) { $entry in
                        HStack(spacing: 8) {
                            // Ressource
                            Picker("", selection: $entry.resource) {
                                ForEach(ResourceKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 200)

                            // Rareté
                            Picker("", selection: $entry.rarity) {
                                ForEach(Rarity.allCases) { r in
                                    Text(r.label).tag(r)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)

                            Spacer()

                            // Quantité
                            TextField("", value: $entry.count, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .onDelete { enc.treasure.resources.remove(atOffsets: $0) }
                }
                .frame(minHeight: 200)
            }

            HStack {
                Button {
                    if !encounter.showTreasureToPlayers {
                        codexDisplay.clear()    // une seule chose à l'écran joueurs
                        worldMap.hide()
                    }
                    encounter.showTreasureToPlayers.toggle()
                } label: {
                    Label(encounter.showTreasureToPlayers ? "Retirer des joueurs" : "Montrer aux joueurs",
                          systemImage: encounter.showTreasureToPlayers ? "tv.slash" : "tv")
                }
                .buttonStyle(.borderedProminent)
                .tint(encounter.showTreasureToPlayers ? .red : .accentColor)
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 540, height: 540)
    }

    private func coinField(_ label: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
    }
}
