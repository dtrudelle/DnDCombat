import SwiftUI
import WebKit

// MARK: - État d'affichage de la carte du monde (côté joueurs)

/// Mécanique calquée sur `CodexDisplayState` : un seul interrupteur partagé entre
/// la fenêtre MJ (qui le bascule) et la fenêtre joueurs (qui affiche l'overlay).
/// Refermer la carte côté MJ la retire de l'écran joueurs.
@Observable
final class WorldMapDisplayState {
    var visible = false

    func toggle() { visible.toggle() }
    func show()   { visible = true }
    func hide()   { visible = false }
}

// MARK: - WebView de la carte (HTML embarqué dans le bundle)

/// Charge `Carte_Tilea_Joueurs.html` depuis les ressources de l'app.
/// La page est autonome (SVG + images base64), donc aucun accès réseau n'est requis.
struct WorldMapWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // Laisse transparaître le fond sombre de la page (évite le flash blanc au chargement).
        web.setValue(false, forKey: "drawsBackground")
        if let url = Self.locateMapFile() {
            print("WorldMap: chargement depuis \(url.path)")
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("WorldMap: ⚠️ Carte_Tilea_Joueurs.html introuvable dans le bundle (\(Bundle.main.bundlePath))")
            web.loadHTMLString(Self.missingHTML, baseURL: nil)
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    /// Recherche le fichier en deux passes : l'appel standard (cas normal, fichier ajouté
    /// comme groupe), puis un balayage récursif du bundle (cas où il a été ajouté en
    /// « référence de dossier » et se trouve donc dans un sous-répertoire des ressources).
    private static func locateMapFile() -> URL? {
        if let direct = Bundle.main.url(forResource: "Carte_Tilea_Joueurs", withExtension: "html") {
            return direct
        }
        guard let resourceRoot = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceRoot, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "Carte_Tilea_Joueurs.html" {
            return url
        }
        return nil
    }

    /// Repli affiché si le fichier n'a pas été ajouté aux ressources du bundle.
    /// Volontairement très visible (rouge) pour ne jamais être confondu avec un écran resté noir.
    private static let missingHTML = """
    <body style="margin:0;background:#3a0f0f;color:#ffe9e9;font-family:-apple-system,sans-serif;\
    display:flex;align-items:center;justify-content:center;height:100vh;text-align:center">
    <div style="max-width:560px">\
    <div style="font-size:48px">⚠️</div>\
    <h1 style="margin:8px 0">Carte introuvable</h1>\
    <p style="font-size:18px;line-height:1.5">Le fichier « Carte_Tilea_Joueurs.html » n'est pas dans le bundle de l'app.<br>\
    Dans Xcode : sélectionnez la cible → <b>Build Phases ▸ Copy Bundle Resources</b><br>\
    et vérifiez qu'il y figure (sinon glissez-le-y).</p>\
    </div>
    </body>
    """
}

// MARK: - Overlay plein écran joueur

/// Recouvre la fenêtre joueurs avec la carte du monde quand le MJ l'affiche.
/// Pleine surface (ce n'est pas une carte « fiche » comme le codex mais LA carte du royaume).
struct WorldMapOverlayView: View {
    var body: some View {
        WorldMapWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .transition(.opacity)
    }
}
