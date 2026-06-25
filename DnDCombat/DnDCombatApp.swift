

import SwiftUI

@main
struct DnDCombatApp: App {
    @State private var library = Library()
    @State private var roster = Roster(members: [
        PCEntry(name: "Personnage 1", initBonus: 2),
        PCEntry(name: "Personnage 2", initBonus: 0),
    ])
    @State private var encounter = Encounter()
    @State private var ui = UIState()
    @State private var store = EncounterStore()
    @State private var codexLibrary = CodexLibrary()
    @State private var codexDisplay = CodexDisplayState()
    @State private var worldMap = WorldMapDisplayState()

    var body: some Scene {
        // Fenêtre du Maître du jeu
        WindowGroup("Maître du jeu") {
            DMView()
                .environment(library)
                .environment(roster)
                .environment(encounter)
                .environment(ui)
                .environment(store)
                .environment(codexLibrary)
                .environment(codexDisplay)
                .environment(worldMap)
                .onAppear { if library.monsters.isEmpty { library.loadBundled() } }
        }
        .commands {
            CommandMenu("Rencontre") {
                Button("Nouvelle rencontre") { encounter.newEncounter() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("Sauvegarder la rencontre…") { ui.showSave = true }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Charger une rencontre…") { ui.showLoad = true }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Ajouter un monstre…") { ui.showAddMonster = true }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Importer un monstre…") { ui.showImport = true }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Bibliothèque de monstres…") { ui.showLibrary = true }
                    .keyboardShortcut("b", modifiers: .command)
                Divider()
                Button("Roster des PJ…") { ui.showRoster = true }
                Divider()
                Button("Codex…") { ui.showCodex = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Fenêtre joueurs (2e écran)
        Window("Écran joueurs", id: "players") {
            PlayerView()
                .environment(encounter)
                .environment(codexLibrary)
                .environment(codexDisplay)
                .environment(worldMap)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
