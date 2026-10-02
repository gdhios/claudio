import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// UI preview mode for development: `Claudio --preview <mode>`
/// with mode ∈ panel, panel-streaming, panel-long, panel-error,
/// panel-noselection, panel-free, panel-free-filled, panel-free-listening,
/// panel-free-unheard, panel-free-noselection, panel-free-answer-track,
/// panel-listening, panel-listening-start,
/// panel-listening-locked, panel-dictation-cleaning, panel-dictation-error, palette, palette-filtre,
/// palette-libre, palette-noselection, listening, listening-streaming, listening-nothing,
/// listening-nokey, settings, settings-dictation, settings-shortcuts-lone-key,
/// settings-streamdeck, toast-pasted, toast-copied.
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

    /// A request made with nothing selected, about the track playing.
    private var shareInstruction: String {
        loc("Écris un message pour partager ce que j'écoute",
            en: "Write a message to share what I'm listening to")
    }

    /// Its answer: a message ready to paste, which leans on the track.
    private var sharedTrackMessage: String {
        loc("En ce moment j'écoute « 真夜中のジョーク » de Takako Mamiya, extrait de LOVE TRIP (1982). De la city pop japonaise comme on n'en fait plus, à écouter d'urgence.",
            en: "Right now I'm listening to “真夜中のジョーク” by Takako Mamiya, from LOVE TRIP (1982). Japanese city pop like they don't make anymore, give it a listen.")
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
        } else if mode == "settings-models" {
            // Every row shows its default: nothing is read from this Mac's
            // preferences, and the local list is the frozen one.
            settingsController.show(initialSection: .models)
        } else if mode == "settings-ollama" {
            settingsController.show(initialSection: .ollama)
        } else if mode == "settings-shortcuts" {
            settingsController.show(initialSection: .shortcuts)
        } else if mode == "settings-shortcuts-lone-key" {
            // "Dictate" on right ⌥ held alone, the dictation rows in view.
            PreviewRun.dictationLoneKeys = [.dictate: .rightOption]
            settingsController.show(initialSection: .shortcuts)
        } else if mode == "settings-music" {
            settingsController.show(initialSection: .music)
        } else if mode == "settings-dictation" {
            // The pane freezes its own history and its model list behind
            // `PreviewRun.isActive`: nothing is read from, or written to,
            // this machine's preferences.
            settingsController.show(initialSection: .dictation)
        } else if mode == "settings-streamdeck" {
            // A frozen bridge: waiting for a plugin, and no plugin in the
            // folder. Set by hand rather than read off this Mac — the shot
            // has to be the same on every machine, and nothing here opens a
            // socket or looks in a folder.
            StreamDeckStatusModel.shared.status = .waiting
            StreamDeckStatusModel.shared.pluginInstalled = false
            settingsController.show(initialSection: .streamDeck)
        } else if mode == "settings-about" {
            settingsController.show(initialSection: .about)
        } else if mode.hasPrefix("toast") {
            // The pill a click on a recent dictation leaves, held long
            // enough for the shot to find it.
            ClipboardToast.shared.show(mode == "toast-copied" ? .copied : .pasted, for: .seconds(60))
        } else if mode == "barre-de-menus" {
            showMenuBarPreview()
        } else if mode.hasPrefix("panel-listening") || mode.hasPrefix("panel-dictation") {
            showDictationPreview()
        } else if mode.hasPrefix("listening") {
            showListeningPreview()
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
        case "panel-free-noselection":
            // The custom action on nothing selected: the same field, asking
            // for a request, and no excerpt under it.
            session = CorrectionSession(request: .awaitingInstruction)
            session.phase = .askingInstruction
        case "panel-free-answer-track":
            // A request made on nothing selected, answered, with the track
            // that went out with it named under the answer, and its Galette
            // buttons. Set by hand: nothing reads this Mac's player, nor
            // looks for Galette on it.
            session = CorrectionSession(request: .free(instruction: shareInstruction))
            session.galette = previewGalette
            session.beginStreaming(sending: sampleTrack(playing: true))
            session.finishStreaming(with: sharedTrackMessage, truncated: false)
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

    /// "What's playing?": the card with Claude's notes, finished or still
    /// coming in over a paused track, then the two ways it stops short. The
    /// session is filled by hand: no coordinator is built, so nothing reads
    /// this Mac's player, nothing is asked of the network, and Galette is
    /// there on every machine.
    private func showListeningPreview() {
        let session = ListeningSession()
        session.galette = previewGalette
        switch mode {
        case "listening-streaming":
            session.track = sampleTrack(playing: false)
            session.artwork = sampleArtwork
            session.facts = sampleFacts
            session.notes = String(sampleNotes.prefix(sampleNotes.count * 2 / 3))
            session.phase = .streaming
        case "listening-nothing":
            session.phase = .nothing
        case "listening-nokey":
            session.track = sampleTrack(playing: true)
            session.phase = .missingKey
        default:  // "listening"
            session.track = sampleTrack(playing: true)
            session.artwork = sampleArtwork
            session.facts = sampleFacts
            session.notes = sampleNotes
            session.phase = .done
        }
        let panel = ResultPanel.make(session: session, textSize: textSize)
        self.panel = panel
        panel.present()
    }

    /// What MusicBrainz says of the sample track (captured 2026-10-02):
    /// the player names the album, so the line shows the year and type.
    private var sampleFacts: TrackFacts {
        TrackFacts(recordingID: "783dfef9-87f4-4056-b944-c7ae624d5964",
                   releaseGroupID: "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb",
                   albumTitle: "LOVE TRIP", primaryType: "Album", secondaryTypes: [],
                   firstReleaseDate: "1982-11-25")
    }

    /// A cover drawn here rather than read anywhere: the same square on
    /// every machine, the night-blue of the sample album.
    private var sampleArtwork: NSImage {
        let size = NSSize(width: 250, height: 250)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.36, alpha: 1),
                                NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.48, alpha: 1)])?
                .draw(in: rect, angle: -60)
            NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70)).fill()
            return true
        }
    }

    /// A track whose metadata isn't in the Latin alphabet: the card shows it
    /// as the player gives it.
    private func sampleTrack(playing: Bool) -> NowPlayingTrack {
        NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP",
                        appName: "Spotify", bundleID: "com.spotify.client",
                        isPlaying: playing, duration: 245)
    }

    /// Galette as if installed, so its buttons show on every machine: the
    /// generic app icon stands in for its own, and no player is a browser.
    private var previewGalette: GaletteApp {
        GaletteApp(icon: NSWorkspace.shared.icon(for: .applicationBundle), browsers: [])
    }

    /// Notes of the kind the prompt asks for: who, where from, one fact.
    private var sampleNotes: String {
        loc("Takako Mamiya est une chanteuse japonaise de city pop. LOVE TRIP, paru en 1982, est son seul album : longtemps confidentiel, il est devenu culte avec le regain d'intérêt pour la city pop sur internet.",
            en: "Takako Mamiya is a Japanese city pop singer. LOVE TRIP, released in 1982, is her only album: long overlooked, it became a cult favourite with the online revival of city pop.")
    }

    /// Palette: the real panel, stopped at the choosing phase — on a
    /// selection, or on nothing at all, where only what works without one is
    /// offered: "What's playing?", then the custom action.
    private func showPalettePreview() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        if mode != "palette-noselection" { session.originalText = sampleText }
        switch mode {
        case "palette-filtre":
            session.paletteQuery = "trad"
        case "palette-libre":
            session.paletteQuery = sampleInstruction
        default:  // "palette", "palette-noselection"
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
