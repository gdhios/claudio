import AppKit
import SwiftUI

/// UI preview mode for development: `Claudio --preview <mode>`, every mode
/// `Scripts/test.sh` renders, plus `panel-long`, `panel-free-filled`,
/// `palette-libre`, `settings-about` and `barre-de-menus`.
/// `--size small|normal|large|extraLarge` forces the panel's text size.
/// `--shot file.png` writes the window to a PNG and quits; without it, the
/// region to capture is printed (top-left, for `screencapture -R`).
/// No global shortcut or menu bar item is installed.
@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let mode: String
    private var panel: ResultPanel?
    private let settingsController = SettingsWindowController()

    init(mode: String) { self.mode = mode }

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
        } else if mode.hasPrefix("settings-") {
            showSettingsPreview()
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
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if let shotIndex = CommandLine.arguments.firstIndex(of: "--shot"),
               CommandLine.arguments.count > shotIndex + 1 {
                writeShot(to: CommandLine.arguments[shotIndex + 1])
            } else {
                printCaptureRect()
            }
        }
    }

    /// `settings-<tab>`, the tab named as in a `claudio://settings/<tab>`
    /// link. Three of them first set what this Mac would otherwise answer.
    /// The Models and Dictation tabs freeze their own lists behind
    /// `PreviewRun.isActive`: nothing is read from, or written to, this
    /// machine's preferences.
    private func showSettingsPreview() {
        var tab = String(mode.dropFirst("settings-".count))
        if tab == "shortcuts-lone-key" {
            // "Dictate" on right ⌥ held alone, the dictation rows in view.
            PreviewRun.dictationLoneKeys = [.dictate: .rightOption]
            tab = "shortcuts"
        }
        if tab == "streamdeck" {
            // A frozen bridge: waiting for a plugin, and no plugin in the
            // folder. Set by hand rather than read off this Mac — the shot
            // has to be the same on every machine, and nothing here opens a
            // socket or looks in a folder.
            StreamDeckStatusModel.shared.status = .waiting
            StreamDeckStatusModel.shared.pluginInstalled = false
        }
        if tab == "ulanzi" {
            // A frozen clock: an address set and the face installed. Nothing
            // is read from this Mac's preferences and no device is called;
            // with no app behind the model, the Test button does nothing.
            UlanziStatusModel.shared.address = "http://192.168.1.22"
            UlanziStatusModel.shared.status = .ready
        }
        let section = SettingsSection(linkName: tab) ?? .general
        settingsController.show(initialSection: section)
    }

    /// Renders the preview window to a PNG.
    ///
    /// Direct view rendering only: it's the one path that depends on no
    /// permission. Capture by the compositor (which would render materials
    /// and the shadow) requires screen-recording authorization and, without
    /// it, silently returns a blank image: a fake preview is worse than no preview.
    private func writeShot(to path: String) {
        guard let window: NSWindow = panel ?? NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("PREVIEW_SHOT=failed")
            fflush(stdout)
            exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? data.write(to: URL(fileURLWithPath: path))
        print("PREVIEW_SHOT=\(path)")
        fflush(stdout)
        exit(0)
    }

    /// Keeps the panel `make` has put on screen: the shot is taken of it.
    private func show(_ panel: ResultPanel) {
        self.panel = panel
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
            session.phase = .error(AnthropicError.http(status: 401, message: "").localizedDescription)
        case "panel-noselection":
            session = CorrectionSession(action: .correct)
            session.phase = .noSelection
        case "panel-free":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = PreviewSamples.sampleText
            session.phase = .askingInstruction
        case "panel-free-filled":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = PreviewSamples.sampleText
            session.instruction = PreviewSamples.sampleInstruction
            session.phase = .askingInstruction
        case "panel-free-listening":
            // The shortcut held: the instruction is being said into the same
            // panel that will stream the answer. Fixed readings, so the shot
            // is the same on every machine — and no microphone is opened.
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = PreviewSamples.sampleText
            session.levels = PreviewSamples.voiceLevels
            session.instruction = PreviewSamples.spokenInstruction
            session.phase = .listeningInstruction
        case "panel-free-unheard":
            session = CorrectionSession(request: .awaitingInstruction)
            session.originalText = PreviewSamples.sampleText
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
            session = CorrectionSession(request: .free(instruction: PreviewSamples.shareInstruction))
            session.galette = PreviewSamples.previewGalette
            session.beginStreaming(sending: PreviewSamples.sampleTrack(playing: true))
            session.finishStreaming(with: PreviewSamples.sharedTrackMessage, truncated: false)
        default:  // "panel"
            session = CorrectionSession(action: .translateEN)
            session.phase = .done
            session.correctedText = "Can you send me the final version before tomorrow's meeting?"
        }
        show(ResultPanel.make(session: session, textSize: textSize))
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
            session.transcript = PreviewSamples.spokenText
            session.cleanedText = PreviewSamples.tidiedText
            session.phase = .cleaning
        case "panel-dictation-error":
            session.fail(with: .languageUnavailable(DictationLanguage.frFR.locale))
        case "panel-listening-start":
            session.levels = PreviewSamples.voiceLevels
            session.phase = .listening
        case "panel-listening-locked":
            session.levels = PreviewSamples.voiceLevels
            session.transcript = PreviewSamples.tidiedText
            session.isLocked = true
            session.phase = .listening
        default:  // "panel-listening"
            session.levels = PreviewSamples.voiceLevels
            session.transcript = PreviewSamples.tidiedText
            session.phase = .listening
        }
        show(ResultPanel.make(session: session, textSize: textSize))
    }

    /// "What's playing?": the card with Claude's notes, finished or still
    /// coming in over a paused track, then the two ways it stops short. The
    /// session is filled by hand: no coordinator is built, so nothing reads
    /// this Mac's player, nothing is asked of the network, and Galette is
    /// there on every machine.
    private func showListeningPreview() {
        let session = ListeningSession()
        session.galette = PreviewSamples.previewGalette
        switch mode {
        case "listening-streaming":
            session.track = PreviewSamples.sampleTrack(playing: false)
            session.artwork = PreviewSamples.sampleArtwork
            session.facts = PreviewSamples.sampleFacts
            session.notes = String(PreviewSamples.sampleNotes.prefix(PreviewSamples.sampleNotes.count * 2 / 3))
            session.phase = .streaming
        case "listening-essay":
            session.track = PreviewSamples.sampleTrack(playing: true)
            session.artwork = PreviewSamples.sampleArtwork
            session.facts = PreviewSamples.sampleFacts
            session.notes = PreviewSamples.sampleNotes
            session.essaySubject = MusicSubject.album(of: PreviewSamples.sampleTrack(playing: true), facts: PreviewSamples.sampleFacts)
            session.essay = PreviewSamples.sampleEssay
            session.phase = .done
        case "listening-nothing":
            session.phase = .nothing
        case "listening-nokey":
            session.track = PreviewSamples.sampleTrack(playing: true)
            session.phase = .missingKey
        default:  // "listening"
            session.track = PreviewSamples.sampleTrack(playing: true)
            session.artwork = PreviewSamples.sampleArtwork
            session.facts = PreviewSamples.sampleFacts
            session.notes = PreviewSamples.sampleNotes
            session.phase = .done
        }
        show(ResultPanel.make(session: session, textSize: textSize))
    }

    /// Palette: the real panel, stopped at the choosing phase — on a
    /// selection, or on nothing at all, where only what works without one is
    /// offered: "What's playing?", then the custom action.
    private func showPalettePreview() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        if mode != "palette-noselection" { session.originalText = PreviewSamples.sampleText }
        switch mode {
        case "palette-filtre":
            session.paletteQuery = "trad"
        case "palette-libre":
            session.paletteQuery = PreviewSamples.sampleInstruction
        default:  // "palette", "palette-noselection"
            break
        }
        session.phase = .choosingAction

        show(ResultPanel.make(session: session, textSize: textSize))
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
