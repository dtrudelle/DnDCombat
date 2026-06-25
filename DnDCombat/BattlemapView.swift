import SwiftUI
import AppKit

/// Affiche une carte (image) avec une grille projetée par-dessus, dans un rectangle
/// au ratio colonnes:lignes pour que les cases restent carrées. Réutilisée par la
/// fenêtre joueurs (plein écran) et par la vignette du MJ.
struct BattlemapView: View {
    let imageData: Data?
    let columns: Int
    let rows: Int
    var showGrid: Bool = true
    var gridColor: Color = Color.white.opacity(0.35)
    var background: Color = .black

    var body: some View {
        GeometryReader { geo in
            let size = mapSize(in: geo.size)
            ZStack {
                background
                mapContent
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay {
                        if showGrid {
                            GridLines(columns: columns, rows: rows)
                                .stroke(gridColor, lineWidth: 1)
                                .frame(width: size.width, height: size.height)
                        }
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        if let data = imageData, let img = NSImage(data: data) {
            // aspect-fit : l'image entière est affichée sans déformation, centrée dans
            // la grille ; les cases non couvertes restent noires (inutilisées au combat).
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color(white: 0.10))
                .overlay {
                    Text("Aucune carte")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    /// Rectangle au ratio columns:rows, ajusté pour tenir dans l'espace dispo → cases carrées.
    private func mapSize(in available: CGSize) -> CGSize {
        guard columns > 0, rows > 0, available.width > 0, available.height > 0 else { return available }
        let target = CGFloat(columns) / CGFloat(rows)
        let avail = available.width / available.height
        if avail > target {
            // espace plus large que la carte → limité par la hauteur (bandes verticales)
            return CGSize(width: available.height * target, height: available.height)
        } else {
            // espace plus haut → limité par la largeur (bandes horizontales)
            return CGSize(width: available.width, height: available.width / target)
        }
    }
}

/// Lignes de grille (verticales + horizontales) couvrant le rectangle.
struct GridLines: Shape {
    let columns: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard columns > 0, rows > 0 else { return p }
        let cw = rect.width / CGFloat(columns)
        let ch = rect.height / CGFloat(rows)
        for i in 0...columns {
            let x = rect.minX + CGFloat(i) * cw
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for j in 0...rows {
            let y = rect.minY + CGFloat(j) * ch
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}
