import AppKit
import SwiftUI

/// Mode aperçu UI pour le développement : `Claudio --preview <mode>`
/// avec mode ∈ panel, panel-streaming, panel-long, panel-error,
/// panel-noselection, settings. Affiche l'élément à une position fixe et
/// imprime la région à capturer (top-left, pour `screencapture -R`).
/// Aucun raccourci global ni item de barre de menus n'est installé.
@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let mode: String
    private var panel: ResultPanel?
    private let settingsController = SettingsWindowController()

    init(mode: String) { self.mode = mode }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if mode == "settings" {
            settingsController.show()
        } else if mode == "settings-prompts" {
            settingsController.show(initialSection: .prompts)
        } else if mode == "settings-shortcuts" {
            settingsController.show(initialSection: .shortcuts)
        } else if mode == "settings-about" {
            settingsController.show(initialSection: .about)
        } else {
            showPanelPreview()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let shotIndex = CommandLine.arguments.firstIndex(of: "--shot"),
               CommandLine.arguments.count > shotIndex + 1 {
                writeShot(to: CommandLine.arguments[shotIndex + 1])
            } else {
                printCaptureRect()
            }
        }
    }

    /// Rend la fenêtre d'aperçu dans un PNG (aucune permission d'enregistrement
    /// d'écran requise pour capturer les fenêtres de son propre process).
    /// Capture via le compositeur (matériaux/vibrancy rendus), repli sur un
    /// rendu direct de la vue sinon.
    private func writeShot(to path: String) {
        guard let window: NSWindow = panel ?? NSApp.windows.first(where: { $0.isVisible }) else {
            print("PREVIEW_SHOT=échec")
            fflush(stdout)
            exit(1)
        }
        let rep: NSBitmapImageRep?
        if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                 CGWindowID(window.windowNumber),
                                                 [.boundsIgnoreFraming, .bestResolution]) {
            rep = NSBitmapImageRep(cgImage: cgImage)
        } else if let view = window.contentView,
                  let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: cached)
            rep = cached
        } else {
            rep = nil
        }
        guard let data = rep?.representation(using: .png, properties: [:]) else { exit(1) }
        try? data.write(to: URL(fileURLWithPath: path))
        print("PREVIEW_SHOT=\(path)")
        fflush(stdout)
        exit(0)
    }

    private func showPanelPreview() {
        let session: CorrectionSession
        switch mode {
        case "panel-streaming":
            session = CorrectionSession(action: .translateEN)
            session.phase = .streaming
            session.correctedText = "Can you send me the final version before"
        case "panel-long":
            session = CorrectionSession(action: .summarize)
            session.phase = .done
            session.correctedText = """
            Points clés de la réunion :
            - Le lancement de la version 2 est confirmé pour la mi-octobre, sous réserve des retours bêta.
            - Marie reprend la coordination avec l'équipe design ; premier point mardi prochain.
            - Le budget marketing est validé, avec une enveloppe supplémentaire pour la presse spécialisée.
            - Les retours clients sur l'onboarding sont majoritairement positifs, mais l'étape 3 reste confuse.
            - Décision : simplifier l'écran de connexion avant la fin du sprint.
            - Prochaine réunion jeudi 14 h, avec démo complète du nouveau parcours.
            """
        case "panel-error":
            session = CorrectionSession(action: .correct)
            session.phase = .error("Réponse invalide de l'API (401) : vérifie ta clé dans les Réglages.")
        case "panel-noselection":
            session = CorrectionSession(action: .correct)
            session.phase = .noSelection
        default:  // "panel"
            session = CorrectionSession(action: .translateEN)
            session.phase = .done
            session.correctedText = "Can you send me the final version before tomorrow's meeting?"
        }
        let panel = ResultPanel.make(session: session)
        self.panel = panel
        let screen = NSScreen.screens.first?.frame ?? .zero
        panel.present(near: NSPoint(x: screen.minX + 480, y: screen.minY + 760))
    }

    /// Coordonnées pour `screencapture -R x,y,w,h` : origine top-left de l'écran principal.
    private func printCaptureRect() {
        let frame: NSRect
        if let panel {
            frame = panel.frame
        } else if let win = NSApp.windows.first(where: { $0.isVisible }) {
            frame = win.frame
        } else {
            print("PREVIEW_RECT=none")
            return
        }
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let margin: CGFloat = 24
        let x = Int(frame.minX - margin)
        let y = Int(screenHeight - frame.maxY - margin)
        let w = Int(frame.width + margin * 2)
        let h = Int(frame.height + margin * 2)
        print("PREVIEW_RECT=\(x),\(y),\(w),\(h)")
        fflush(stdout)  // stdout redirigé vers un fichier = bufferisé
    }
}
