import SwiftUI

/// The panel for "What's playing?": the track's card as soon as the player
/// has answered, Claude's notes streaming in under it. Its own view, like
/// the dictation's: no selection, no palette, nothing to paste — a card, a
/// text, and the messages that stand in for the text when there is none.
struct ListeningPanelView: View {
    @ObservedObject var session: ListeningSession
    /// Body text size, read once when the panel is built, like the other
    /// panels: the setting applies to the next one.
    var textSize: PanelTextSize = .normal
    let actions: ListeningPanelActions
    var onHeightChange: (@MainActor @Sendable (CGFloat) -> Void)? = nil

    @State private var notesHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // While the player is first being read there is nothing under
            // the header yet, not even an empty band.
            if session.phase != .reading || session.track != nil {
                ClaudioTheme.panelSeparator.frame(height: 1)
                content
            }
            ClaudioTheme.panelSeparator.frame(height: 1)
            footer
        }
        .panelChrome(width: textSize.panelWidth, onHeightChange: onHeightChange)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ClaudioMascot(gaze: .init(session.phase))
            Text("Claudio").font(.headline)
            StatusPill {
                Image(systemName: ListeningSession.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ListeningSession.tint)
                Text(ListeningSession.panelTitle)
            }
            Spacer()
            statusLabel
            PanelCloseButton(action: actions.close)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .reading:
            WorkingPill(loc("Écoute…", en: "Checking…"))
        case .streaming:
            WorkingPill(loc("Rédaction…", en: "Writing…"))
                .id(session.essaySubject)
        case .done:
            ReadyPill()
        case .nothing, .missingKey, .error:
            EmptyView()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let track = session.track {
                ListeningCardView(session: session, track: track, textSize: textSize, actions: actions)
            }
            underCard
        }
    }

    /// What goes under the card: Claude's notes, or what stands in for them.
    @ViewBuilder private var underCard: some View {
        switch session.phase {
        case .reading:
            EmptyView()
        case .nothing:
            messageView(icon: "speaker.slash",
                        title: loc("Rien en lecture", en: "Nothing playing"),
                        detail: loc("Lance un morceau, puis redemande.",
                                    en: "Start a track, then ask again."))
        case .streaming, .done:
            notes
        case .missingKey:
            messageView(icon: "key",
                        title: loc("Clé API manquante", en: "No API key"),
                        detail: loc("Ajoute ta clé Anthropic dans les Réglages pour que Claude te parle de ce morceau.",
                                    en: "Add your Anthropic key in Settings so Claude can tell you about this track."))
        case .error(let message):
            messageView(icon: "exclamationmark.triangle",
                        title: loc("Erreur", en: "Error"),
                        detail: message)
        }
    }

    /// Claude's notes: a caret while they come in, plain text once done.
    /// Three sentences fit; a longer answer scrolls past the panel's usual
    /// ceiling rather than pushing it off the screen.
    private var notes: some View {
        ScrollView {
            StreamingText(text: shownText, isStreaming: session.phase == .streaming)
                .font(.system(size: textSize.bodyPoints))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .reportsHeight(PanelTextHeightKey.self)
        }
        .frame(height: min(notesHeight, textSize.maxTextHeight))
        .onPreferenceChange(PanelTextHeightKey.self) { height in
            // Interpolated, as in the other panels: the measured height
            // jumps a line at a time, and the window follows it smoothly.
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.18)) { notesHeight = height }
            }
        }
    }

    /// The notes, or the long text when a subject is on screen.
    private var shownText: String {
        session.essaySubject == nil ? session.notes : session.essay
    }

    private func messageView(icon: String, title: String, detail: String) -> some View {
        // Under a card, the card already makes room above.
        PanelMessage(icon: icon, title: title, detail: detail, textSize: textSize,
                     top: session.track == nil ? 26 : 14, bottom: 22)
    }

    /// The model is named once it has something to do with what is on
    /// screen: not over "Nothing playing", nor over a missing key.
    private var showsModelName: Bool {
        switch session.phase {
        case .reading, .streaming, .done, .error: true
        case .nothing, .missingKey: false
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PanelFooterCaption(model: showsModelName ? session.model.shortName : nil)
            Spacer()
            // Under the long text: the same subject, in Claude's browser. The
            // footer is narrow: the site's name says where it goes.
            if let subject = session.essaySubject, session.phase != .missingKey {
                Button("claude.ai") { actions.search(subject) }
                    .buttonStyle(PanelPillButtonStyle())
                    .help(ListeningCardView.searchHelp)
            }
            // The way back to the notes, when there are notes to go back to.
            if session.essaySubject != nil, !session.cameFromLink {
                Button(loc("Retour", en: "Back"), action: actions.back)
                    .buttonStyle(PanelPillButtonStyle())
            }
            switch session.phase {
            case .missingKey:
                Button(loc("Réglages…", en: "Settings…"), action: actions.openSettings)
                    .buttonStyle(PanelPillButtonStyle())
            case .error:
                Button(loc("Réessayer", en: "Try again"), action: actions.retry)
                    .buttonStyle(PanelPillButtonStyle())
            case .reading, .nothing, .streaming, .done:
                EmptyView()
            }
            // Back to the player the track came from, where its favourite
            // button is: as soon as the card knows the app behind it. Not
            // under the long text, whose footer is full already.
            if session.essaySubject == nil, let player = session.track?.playerName {
                Button(loc("Ouvrir \(player)", en: "Open \(player)"), action: actions.openPlayer)
                    .buttonStyle(PanelPillButtonStyle())
                    .help(loc("Ramène le lecteur au premier plan et ferme ce panneau",
                              en: "Brings the player forward and closes this panel"))
            }
            // Always last, whatever the phase: it copies the card, and ⌘C
            // works as soon as the card is up.
            if session.track != nil {
                CopyButton(justCopied: session.justCopied, action: actions.copy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// What the listening panel's buttons do: built once, by the coordinator
/// that owns the panel, and handed down whole. The preview's does nothing.
struct ListeningPanelActions {
    var copy: () -> Void = {}
    var retry: () -> Void = {}
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    var openInGalette: (GaletteLink) -> Void = { _ in }
    /// "Tell me more": the long text on a subject, in place of the notes.
    var elaborate: (MusicSubject) -> Void = { _ in }
    /// From the long text back to the notes.
    var back: () -> Void = {}
    /// The subject in Claude, which searches the web.
    var search: (MusicSubject) -> Void = { _ in }
    var openPlayer: () -> Void = {}
}
