import AppKit
import SwiftUI

/// UI preview mode for development: `Claudio --preview <mode>`
/// with mode ∈ panel, panel-streaming, panel-long, panel-error,
/// panel-noselection, panel-free, panel-free-filled, panel-free-listening,
/// panel-free-unheard, panel-listening, panel-listening-start,
/// panel-listening-locked, panel-dictation-cleaning, panel-dictation-error, palette, palette-filtre,
/// palette-libre, settings, settings-dictation, settings-shortcuts-lone-key.
/// `--size small|normal|large|extraLarge` forces the panel's text size.
/// Shows the element at a fixed position and
/// prints the region to capture (top-left, for `screencapture -R`).
/// No global shortcut or menu bar item is installed.
/// True when the app is running in preview (`--preview`). A view uses it to
/// avoid asking the network for anything: a preview must render the same
/// screen on every machine, including a CI runner where nothing is listening
/// (TESTING.md, level 2).
enum PreviewRun {
    static let isActive = CommandLine.arguments.contains("--preview")

    /// The lone keys a preview shows on the dictation shortcuts: none unless
    /// its mode sets one, and never this Mac's. A preview that sets one is
    /// about those rows, and scrolls down to them.
    @MainActor static var dictationLoneKeys: [DictationShortcut: LoneModifierKey] = [:]
}

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let mode: String
    private var panel: ResultPanel?
    private let settingsController = SettingsWindowController()

    init(mode: String) { self.mode = mode }

    /// Sample text for previews: an email written quickly, with the typos
    /// that come with it. It follows the interface's language: an English
    /// capture whose selection is in French wouldn't show what it advertises.
    private var sampleText: String {
        loc("Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance",
            en: "Hi, i wanted to know if you could send me the document before tomorow morning. thanks in advance")
    }

    /// Sample instruction for the custom-action previews.
    private var sampleInstruction: String {
        loc("Traduis en espagnol", en: "Translate to Spanish")
    }

    /// The same instruction being said rather than typed, caught
    /// mid-sentence: the shortcut is still held.
    private var spokenInstruction: String {
        loc("Traduis ce message en ", en: "Translate this message to ")
    }

    /// Preview's text size: `--size large`, otherwise the current setting.
    private var textSize: PanelTextSize {
        guard let index = CommandLine.arguments.firstIndex(of: "--size"),
              CommandLine.arguments.count > index + 1,
              let size = PanelTextSize(rawValue: CommandLine.arguments[index + 1]) else {
            return AppSettings.panelTextSize
        }
        return size
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if mode == "settings" {
            settingsController.show()
        } else if mode == "settings-prompts" {
            settingsController.show(initialSection: .prompts)
        } else if mode == "settings-ollama" {
            settingsController.show(initialSection: .ollama)
        } else if mode == "settings-shortcuts" {
            settingsController.show(initialSection: .shortcuts)
        } else if mode == "settings-shortcuts-lone-key" {
            // "Dictate" on right ⌥ held alone, the dictation rows in view.
            PreviewRun.dictationLoneKeys = [.dictate: .rightOption]
            settingsController.show(initialSection: .shortcuts)
        } else if mode == "settings-dictation" {
            // The pane freezes its own history and its model list behind
            // `PreviewRun.isActive`: nothing is read from, or written to,
            // this machine's preferences.
            settingsController.show(initialSection: .dictation)
        } else if mode == "settings-about" {
            settingsController.show(initialSection: .about)
        } else if mode == "barre-de-menus" {
            showMenuBarPreview()
        } else if mode.hasPrefix("panel-listening") || mode.hasPrefix("panel-dictation") {
            showDictationPreview()
        } else if mode.hasPrefix("palette") {
            showPalettePreview()
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

    /// Renders the preview window to a PNG.
    ///
    /// Direct view rendering first: it's the only path that depends on no
    /// permission. Capture by the compositor (which would render materials
    /// and the shadow) requires screen-recording authorization and, without
    /// it, silently returns a blank image: a fake preview is worse than no preview.
    private func writeShot(to path: String) {
        guard let window: NSWindow = panel ?? NSApp.windows.first(where: { $0.isVisible }) else {
            print("PREVIEW_SHOT=échec")
            fflush(stdout)
            exit(1)
        }
        let rep: NSBitmapImageRep?
        if let view = window.contentView,
           let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: cached)
            rep = cached
        } else if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                       CGWindowID(window.windowNumber),
                                                       [.boundsIgnoreFraming, .bestResolution]) {
            rep = NSBitmapImageRep(cgImage: cgImage)
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
        case "panel-free":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = sampleText
            session.phase = .askingInstruction
        case "panel-free-filled":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = sampleText
            session.instruction = sampleInstruction
            session.phase = .askingInstruction
        case "panel-free-listening":
            // The shortcut held: the instruction is being said into the same
            // panel that will stream the answer. Fixed readings, so the shot
            // is the same on every machine — and no microphone is opened.
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = sampleText
            session.levels = voiceLevels
            session.instruction = spokenInstruction
            session.phase = .listeningInstruction
        case "panel-free-unheard":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = sampleText
            session.phase = .instructionNotHeard(reason: nil)
        default:  // "panel"
            session = CorrectionSession(action: .translateEN)
            session.phase = .done
            session.correctedText = "Can you send me the final version before tomorrow's meeting?"
        }
        let panel = ResultPanel.make(session: session, textSize: textSize)
        self.panel = panel
        panel.present()
    }

    /// Dictation: the panel while listening, held or locked by a tap, while
    /// the cleanup streams, and when the language isn't installed. No engine
    /// is ever built here and the microphone is never opened. The language
    /// and the model are fixed rather than read from the settings: a preview
    /// renders the same screen on every machine, including one where nothing
    /// is listening.
    private func showDictationPreview() {
        let session = DictationSession(language: .frFR, model: .claude(.haiku45))
        switch mode {
        case "panel-dictation-cleaning":
            session.transcript = spokenText
            session.cleanedText = tidiedText
            session.phase = .cleaning
        case "panel-dictation-error":
            session.fail(with: .languageUnavailable(DictationLanguage.frFR.locale))
        case "panel-listening-start":
            session.levels = voiceLevels
            session.phase = .listening
        case "panel-listening-locked":
            session.levels = voiceLevels
            session.transcript = tidiedText
            session.isLocked = true
            session.phase = .listening
        default:  // "panel-listening"
            session.levels = voiceLevels
            session.transcript = tidiedText
            session.phase = .listening
        }
        let panel = ResultPanel.make(session: session, textSize: textSize)
        self.panel = panel
        panel.present()
    }

    /// A voice starting in a quiet room: flat, then a phrase with its rises
    /// and a breath. Fixed values, so the shot is the same on every machine.
    private var voiceLevels: LevelHistory {
        let readings: [Float] = [0, 0, 0.02, 0, 0.05, 0.1, 0.35, 0.62, 0.48, 0.7, 0.85, 0.55,
                                 0.3, 0.12, 0.08, 0.4, 0.66, 0.9, 0.72, 0.5, 0.58, 0.8, 0.45, 0.2,
                                 0.1, 0.3, 0.55, 0.75, 0.6, 0.38, 0.52, 0.68]
        return readings.reduce(LevelHistory()) { $0.adding($1) }
    }

    /// A dictation as it comes out of speech recognition: no punctuation, a
    /// hesitation, and the speaker correcting themselves.
    private var spokenText: String {
        loc("euh bonjour je voulais te dire que la réunion de mardi non mercredi est décalée à quatorze heures",
            en: "uh hi i wanted to tell you that tuesday's no wednesday's meeting is pushed to two pm")
    }

    /// The same dictation being tidied up, caught mid-sentence.
    private var tidiedText: String {
        loc("Bonjour, je voulais te dire que la réunion de ",
            en: "Hi, I wanted to tell you that Wednesday's meeting ")
    }

    /// Palette: the real panel, stopped at the choosing phase.
    private func showPalettePreview() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = sampleText
        switch mode {
        case "palette-filtre":
            session.paletteQuery = "trad"
        case "palette-libre":
            session.paletteQuery = sampleInstruction
        default:  // "palette"
            break
        }
        session.phase = .choosingAction

        let panel = ResultPanel.make(session: session, textSize: textSize)
        self.panel = panel
        panel.present()
    }

    /// Claudio in the menu bar, at his real size then enlarged, on a light
    /// background and on a dark one: that's where readability gets judged.
    private func showMenuBarPreview() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 232),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Regards"
        window.contentView = MenuBarPreviewView(frame: NSRect(x: 0, y: 0, width: 460, height: 232))
        let screen = NSScreen.screens.first?.frame ?? .zero
        window.setFrameOrigin(NSPoint(x: screen.minX + 480, y: screen.minY + 760))
        window.makeKeyAndOrderFront(nil)
    }

    /// Coordinates for `screencapture -R x,y,w,h`: top-left origin of the main screen.
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
        fflush(stdout)  // stdout redirected to a file = buffered
    }
}


/// The four gazes on the menu bar's two backgrounds: at their real size,
/// then enlarged without smoothing. That's where readability gets judged: a
/// gaze that can't be told apart here is useless in the app.
private final class MenuBarPreviewView: NSView {
    private let regards: [(String, ClaudioMascot.Gaze)] = [
        ("repos", .repos), ("veille", .veille), ("fait", .fait), ("vide", .vide),
    ]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let fonds: [(NSColor, NSColor)] = [
            (NSColor(white: 0.96, alpha: 1), .black),   // light bar
            (NSColor(white: 0.11, alpha: 1), .white),   // dark bar
        ]
        let colonne: CGFloat = 104, bande: CGFloat = 116

        for (rang, (fond, encre)) in fonds.enumerated() {
            let haut = CGFloat(rang) * bande
            fond.setFill()
            NSRect(x: 0, y: haut, width: bounds.width, height: bande).fill()

            for (index, (nom, gaze)) in regards.enumerated() {
                let x = 20 + CGFloat(index) * colonne
                let image = ClaudioMascot.menuBarImage(gaze: gaze).teinte(encre)
                let taille = image.size

                NSAttributedString(string: nom, attributes: [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: encre.withAlphaComponent(0.55),
                ]).draw(at: NSPoint(x: x, y: haut + 10))

                // Real size, that of the menu bar.
                image.draw(in: NSRect(x: x, y: haut + 28,
                                      width: taille.width, height: taille.height))

                // Enlarged threefold, visible pixels.
                NSGraphicsContext.current?.imageInterpolation = .none
                image.draw(in: NSRect(x: x, y: haut + 54,
                                      width: taille.width * 3, height: taille.height * 3))
                NSGraphicsContext.current?.imageInterpolation = .default
            }
        }
    }
}

private extension NSImage {
    /// A template image only carries its alpha: here is its inked version.
    func teinte(_ couleur: NSColor) -> NSImage {
        let copie = NSImage(size: size)
        copie.lockFocus()
        draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        couleur.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        copie.unlockFocus()
        return copie
    }
}
