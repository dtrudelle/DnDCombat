import SwiftUI
import AppKit

struct PlayerView: View {
    @Environment(Encounter.self) private var enc
    @Environment(CodexLibrary.self) private var codex
    @Environment(CodexDisplayState.self) private var codexDisplay
    @Environment(WorldMapDisplayState.self) private var worldMap

    var body: some View {
        VStack(spacing: 0) {
            banner
            mapArea
        }
        .background(Color.black)
        .background(WindowConfigurator())
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            if worldMap.visible {
                WorldMapOverlayView()
                    .animation(.easeInOut(duration: 0.2), value: worldMap.visible)
            } else if let id = codexDisplay.pushedID,
               let entry = codex.entries.first(where: { $0.id == id }) {
                CodexOverlayView(entry: entry)
                    .animation(.easeInOut(duration: 0.2), value: codexDisplay.pushedID)
            } else if enc.showTreasureToPlayers {
                TreasureOverlayView(treasure: enc.treasure)
                    .animation(.easeInOut(duration: 0.2), value: enc.showTreasureToPlayers)
            }
        }
    }

    // MARK: Bandeau d'initiative (haut)

    private var banner: some View {
        HStack(spacing: 18) {
            roundBadge
            if enc.order.isEmpty {
                Text("En attente du combat…")
                    .font(.title3).foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(queue.enumerated()), id: \.element.id) { index, entry in
                            chip(entry, isActive: index == 0)
                        }
                    }
                    .padding(.horizontal, 4)
                    .animation(.easeInOut(duration: 0.25), value: enc.activeID)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.12))
    }

    private var roundBadge: some View {
        VStack(spacing: -2) {
            Text("ROUND")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.55))
            Text(enc.round > 0 ? "\(enc.round)" : "–")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white).monospacedDigit()
        }
        .fixedSize()
    }

    private func chip(_ entry: InitiativeEntry, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.initiative)")
                .font(.title3.weight(.heavy)).monospacedDigit()
                .foregroundStyle(isActive ? .white : .white.opacity(0.7))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(isActive ? .title2.weight(.bold) : .title3)
                    .foregroundStyle(isActive ? .white : .white.opacity(0.8))
                    .lineLimit(1)
                if case .monsters(let g) = entry {
                    GroupHPBars(group: g)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.accentColor : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(isActive ? 0.7 : 0.0), lineWidth: 1.5)
        )
    }

    // MARK: Zone carte (pleine taille)

    private var mapArea: some View {
        BattlemapView(imageData: enc.mapImageData,
                      columns: enc.gridColumns,
                      rows: enc.gridRows,
                      showGrid: enc.showGrid)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // File d'initiative ré-enracinée sur la créature active (active en tête, puis les suivantes)
    private var queue: [InitiativeEntry] {
        guard let activeID = enc.activeID,
              let idx = enc.order.firstIndex(where: { $0.id == activeID }) else {
            return enc.order
        }
        return Array(enc.order[idx...]) + Array(enc.order[..<idx])
    }
}

// MARK: - Barres de PV (vue joueurs)

/// Une mini-barre par instance du groupe, côte à côte. Donne une idée relative
/// de l'état de santé sans révéler de chiffres aux joueurs.
private struct GroupHPBars: View {
    let group: MonsterGroup

    var body: some View {
        HStack(spacing: 3) {
            ForEach(group.instances) { inst in
                HPBar(inst: inst, width: group.instances.count == 1 ? 80 : 28)
            }
        }
    }
}

/// Petite barre par instance. Tant que les PV sont > 0, elle montre le % de PV
/// (vert/orange/rouge). Dès 0 PV, elle bascule en rouge et montre le % de wounds
/// restants ; à 0 wound elle est vide (hors-combat).
private struct HPBar: View {
    let inst: MonsterInstance
    var width: CGFloat = 28

    private var woundMode: Bool { inst.currentHP <= 0 }

    private var fraction: Double {
        if woundMode {
            return inst.maxWounds > 0 ? Double(inst.currentWounds) / Double(inst.maxWounds) : 0
        }
        return inst.maxHP > 0 ? Double(inst.currentHP) / Double(inst.maxHP) : 0
    }

    // Deux rouges distincts : rouge vif quand les PV sont critiques (mode PV),
    // rouge sang sombre quand on est passé en territoire de wounds (PV à 0).
    private static let woundRed = Color(red: 0.62, green: 0.04, blue: 0.12)

    private var color: Color {
        if inst.currentWounds <= 0 { return .white.opacity(0.25) }   // hors-combat
        if woundMode { return Self.woundRed }                         // 0 PV → wounds en rouge sombre
        switch fraction {                                             // mode PV
        case ..<0.25: return .red                                     // PV critiques : rouge vif
        case ..<0.5:  return .orange
        default:      return .green
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: proxy.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(width: width, height: 9)
    }
}

/// Active le vrai plein écran (bouton vert) sur la fenêtre joueurs : la barre de
/// menus se masque automatiquement en plein écran natif, ce que ne fait pas le zoom.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Overlay Trésor (vue joueurs)

/// Affiché par-dessus la carte quand le MJ pousse le trésor (`Encounter.showTreasureToPlayers`).
/// Même habillage que l'overlay du codex : carte sombre centrée sur fond assombri.
struct TreasureOverlayView: View {
    let treasure: Treasure

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) { Spacer(); content; Spacer() }
            Spacer()
        }
        .background(Color.black.opacity(0.55))
        .transition(.opacity)
    }

    private var content: some View {
        VStack(spacing: 18) {
            Text("Loot!!!")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            if let coins = coinsLine {
                Text(coins)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.80, blue: 0.40))
                    .monospacedDigit()
            }

            if !treasure.resources.isEmpty {
                VStack(spacing: 10) {
                    ForEach(treasure.resources) { r in
                        HStack(spacing: 12) {
                            Text(r.resource)
                                .font(.title3)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("×\(r.count)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .monospacedDigit()
                            Text(r.rarity.label)
                                .font(.headline)
                                .foregroundStyle(rarityColor(r.rarity))
                                .frame(width: 140, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: 540)
            }

            if !treasure.notes.isEmpty {
                Text(treasure.notes)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
        .padding(36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .shadow(radius: 20)
        )
        .padding(40)
    }

    private var coinsLine: String? {
        var parts: [String] = []
        if treasure.aureon != 0  { parts.append("\(treasure.aureon) Auréon") }
        if treasure.solari != 0  { parts.append("\(treasure.solari) Solari") }
        if treasure.scaille != 0 { parts.append("\(treasure.scaille) Scaille") }
        return parts.isEmpty ? nil : parts.joined(separator: "   ·   ")
    }

    private func rarityColor(_ r: Rarity) -> Color {
        switch r {
        case .common:    return .white.opacity(0.7)
        case .uncommon:  return .green
        case .rare:      return .blue
        case .veryRare:  return .purple
        case .legendary: return .orange
        }
    }
}
