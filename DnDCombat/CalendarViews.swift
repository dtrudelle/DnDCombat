import SwiftUI

// MARK: - Feuille Calendrier (MJ)

struct CalendarSheet: View {
    @Environment(CalendarLibrary.self) private var cal
    @Environment(CalendarDisplayState.self) private var display
    @Environment(CodexDisplayState.self) private var codexDisplay
    @Environment(WorldMapDisplayState.self) private var worldMap
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    /// Jour consulté dans l'agenda (par défaut le jour courant ; on peut feuilleter
    /// le passé et le futur pour y noter des événements).
    @State private var viewedOrdinal = 0
    @State private var selectedID: CalendarEvent.ID?
    @State private var didInit = false

    var body: some View {
        HSplitView {
            agendaColumn
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 480)
            editorColumn
                .frame(minWidth: 360)
        }
        .frame(width: 900, height: 620)
        .onAppear {
            if !didInit { viewedOrdinal = cal.currentOrdinal; didInit = true }
        }
        .onDisappear { display.hide() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { display.hide(); dismiss() }
            }
        }
    }

    private var viewedDate: TileaDate { TileaDate(ordinal: viewedOrdinal) }
    private var isViewingToday: Bool { viewedOrdinal == cal.currentOrdinal }

    // MARK: Colonne agenda (horloge + navigation + liste des événements)

    private var agendaColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            clockHeader
            Divider()
            dayNavigator
            Divider()
            eventList
            Divider()
            pushButton
                .padding(10)
        }
    }

    // MARK: Horloge de campagne (« maintenant »)

    private var clockHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date de campagne").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(cal.currentDate.moonSymbol).font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cal.currentDate.longLabel)
                        .font(.headline).monospacedDigit()
                    HStack(spacing: 6) {
                        Text(cal.currentPart.label)
                        Text("·")
                        Text("\(cal.currentDate.season.symbol) \(cal.currentDate.season.name)")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let f = cal.currentDate.festival {
                Label("\(f.symbol) \(f.name)", systemImage: "star.fill")
                    .font(.callout).foregroundStyle(.orange)
            }

            // Contrôles d'avancement du temps.
            HStack(spacing: 6) {
                Button { cal.stepPart(forward: false) } label: { Image(systemName: "chevron.left") }
                    .help("Créneau précédent")
                Text(cal.currentPart.label)
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 78)
                Button { cal.stepPart(forward: true) } label: { Image(systemName: "chevron.right") }
                    .help("Créneau suivant")

                Divider().frame(height: 16)

                Button("−1 j") { cal.stepDay(-1) }
                Button("+1 j") { cal.stepDay(1) }
                Button { cal.longRest() } label: { Label("Repos long", systemImage: "bed.double") }
                    .help("Avance au matin du jour suivant")
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(10)
    }

    // MARK: Navigateur de jour (agenda)

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            Button { viewedOrdinal -= 1 } label: { Image(systemName: "chevron.left") }
                .help("Jour précédent")

            VStack(spacing: 1) {
                Text(viewedDate.longLabel)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(viewedDate.moonSymbol)  \(viewedDate.season.symbol) \(viewedDate.season.name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { viewedOrdinal += 1 } label: { Image(systemName: "chevron.right") }
                .help("Jour suivant")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .topTrailing) {
            if !isViewingToday {
                Button("Aujourd'hui") { viewedOrdinal = cal.currentOrdinal }
                    .controlSize(.mini)
                    .padding(.trailing, 10)
            }
        }
    }

    // MARK: Liste des événements du jour consulté

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Événements").font(.headline)
                Spacer()
                Button {
                    let new = CalendarEvent(ordinal: viewedOrdinal)
                    cal.upsert(new)
                    selectedID = new.id
                } label: { Image(systemName: "plus") }
                .help("Nouvel événement ce jour")
            }
            .padding([.horizontal, .top], 10)

            let items = cal.events(on: viewedOrdinal)
            if items.isEmpty {
                VStack {
                    Spacer()
                    Text("Aucun événement ce jour.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(items) { ev in
                        eventRow(ev).tag(ev.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ev.part.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(ev.titre.isEmpty ? "Sans titre" : ev.titre)
                Text(ev.part.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ev.visibleJoueurs {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .help("Visible des joueurs")
            }
        }
    }

    // MARK: Bouton push écran joueurs

    private var pushButton: some View {
        Button {
            if !display.visible {        // une seule chose à l'écran joueurs
                codexDisplay.clear()
                worldMap.hide()
                enc.showTreasureToPlayers = false
            }
            display.toggle()
        } label: {
            Label(display.visible ? "Retirer des joueurs" : "Afficher le calendrier aux joueurs",
                  systemImage: display.visible ? "tv.slash" : "tv")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(display.visible ? .red : .accentColor)
    }

    // MARK: Colonne éditeur

    private var editorColumn: some View {
        Group {
            if let id = selectedID, cal.events.contains(where: { $0.id == id }) {
                CalendarEventEditor(event: binding(for: id),
                                    onSave: { cal.save() },
                                    onDelete: {
                                        cal.delete(id)
                                        selectedID = nil
                                    })
            } else {
                VStack {
                    Spacer()
                    Text("Sélectionnez ou créez un événement.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Binding construit à la main vers l'événement d'`id` donné (comme le codex).
    private func binding(for id: CalendarEvent.ID) -> Binding<CalendarEvent> {
        Binding(
            get: { cal.events.first(where: { $0.id == id }) ?? CalendarEvent(ordinal: viewedOrdinal) },
            set: { newValue in
                if let i = cal.events.firstIndex(where: { $0.id == id }) {
                    cal.events[i] = newValue
                }
            }
        )
    }
}

// MARK: - Éditeur d'événement

private struct CalendarEventEditor: View {
    @Binding var event: CalendarEvent
    var onSave: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $event.titre)
                    .onChange(of: event.titre) { _, _ in onSave() }

                Picker("Créneau", selection: $event.part) {
                    ForEach(DayPart.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .onChange(of: event.part) { _, _ in onSave() }

                // Déplacement du jour (créneau conservé).
                HStack {
                    Text("Jour")
                    Spacer()
                    Text(event.date.longLabel)
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button { event.ordinal -= 1; onSave() } label: { Image(systemName: "chevron.left") }
                    Button { event.ordinal += 1; onSave() } label: { Image(systemName: "chevron.right") }
                }
                .controlSize(.small)
            }

            Section("Note joueur (visible des joueurs)") {
                TextEditor(text: $event.noteJoueur)
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    .onChange(of: event.noteJoueur) { _, _ in onSave() }
            }

            Section("Note MJ (privée)") {
                TextEditor(text: $event.noteMJ)
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                    .onChange(of: event.noteMJ) { _, _ in onSave() }
            }

            Section {
                Toggle(isOn: $event.visibleJoueurs) {
                    Label("Visible des joueurs", systemImage: "eye")
                }
                .onChange(of: event.visibleJoueurs) { _, _ in onSave() }
                Text("Si activé, les joueurs voient le titre et la note joueur (jamais la note MJ).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive, action: onDelete) {
                    Label("Supprimer l'événement", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Overlay côté joueur

/// Affiché par-dessus la carte quand le MJ pousse le calendrier. Montre le jour
/// courant et les deux jours suivants ; uniquement les événements rendus visibles
/// (titre + note joueur), jamais les notes MJ.
struct CalendarOverlayView: View {
    @Environment(CalendarLibrary.self) private var cal

    var body: some View {
        let start = cal.currentDate
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                Text("an \(start.year) — \(TileaCalendar.eraSuffix)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(alignment: .top, spacing: 18) {
                    ForEach(0..<3, id: \.self) { offset in
                        dayCard(date: start.adding(days: offset), isToday: offset == 0)
                    }
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.11))
                    .shadow(radius: 24)
            )
            .padding(40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .transition(.opacity)
    }

    private func dayCard(date: TileaDate, isToday: Bool) -> some View {
        let events = cal.visibleEvents(on: date.ordinal)
        return VStack(alignment: .leading, spacing: 14) {
            // En-tête date.
            VStack(alignment: .leading, spacing: 3) {
                Text(date.weekdayName.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isToday ? Color.accentColor : .white.opacity(0.5))
                Text("\(date.day) \(date.monthName)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Saison + lune.
            HStack(spacing: 14) {
                Text("\(date.season.symbol) \(date.season.name)")
                Text(date.moonSymbol)
            }
            .font(.title3)
            .foregroundStyle(.white.opacity(0.85))

            // Fête éventuelle.
            if let f = date.festival {
                Text("\(f.symbol) \(f.name)")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.93, green: 0.80, blue: 0.40))
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Événements visibles.
            if events.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { ev in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: ev.part.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(ev.titre)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            if !ev.noteJoueur.isEmpty {
                                Text(ev.noteJoueur)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 280, height: 360, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isToday ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isToday ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08),
                              lineWidth: isToday ? 2 : 1)
        )
    }
}
