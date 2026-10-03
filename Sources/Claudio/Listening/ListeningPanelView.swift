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
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    var onOpenInGalette: (GaletteLink) -> Void = { _ in }
    var onElaborate: (MusicSubject) -> Void = { _ in }
    var onBack: () -> Void = {}
    var onSearch: (MusicSubject) -> Void = { _ in }
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
        .frame(width: textSize.panelWidth)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ListeningPanelHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(ListeningPanelHeightKey.self) { [onHeightChange] height in
            MainActor.assumeIsolated { onHeightChange?(height) }
        }
        .background(ClaudioTheme.panelBackground,
                    in: RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(ClaudioTheme.panelBorder, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
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
            PanelCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .reading:
            workingPill(loc("Écoute…", en: "Checking…"))
        case .streaming:
            workingPill(loc("Rédaction…", en: "Writing…"))
                .id(session.essaySubject)
        case .done:
            StatusPill(background: .green.opacity(0.16), foreground: .green) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Text(loc("Prêt", en: "Ready"))
            }
        case .nothing, .missingKey, .error:
            EmptyView()
        }
    }

    private func workingPill(_ label: String) -> some View {
        StatusPill {
            ProgressView().controlSize(.mini)
            Text(label)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let track = session.track {
                card(track)
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

    /// The track as its player names it, then the way to it in Galette when
    /// this Mac has Galette — from the moment the card is up.
    private func card(_ track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let artwork = session.artwork {
                    cover(artwork)
                }
                trackText(track)
            }
            .animation(.easeOut(duration: 0.18), value: session.artwork == nil)
            // Two rows: the ways to Galette, then the ways to Claude. Side
            // by side, the three subjects and the search overflowed the card.
            if let buttons = GaletteButtons(galette: session.galette, links: session.galetteLinks,
                                            onOpen: onOpenInGalette) {
                buttons
            }
            if showsSubjectPills {
                subjectPills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, session.phase == .reading ? 12 : 2)
    }

    /// The player's cover, the size of three lines of card: it arrives
    /// after the text and slides in beside it.
    private func cover(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: textSize.points(52), height: textSize.points(52))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    /// "Tell me more" is offered once there is a card and a Claude to ask:
    /// not over a missing key, and not while the long text is on screen.
    private var showsSubjectPills: Bool {
        guard session.phase != .missingKey, !session.subjects.isEmpty else { return false }
        return true
    }

    /// One pill per subject the card knows: the album, the artist.
    private var subjectPills: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ForEach(session.subjects, id: \.self) { subject in
                Button(subject.buttonTitle) { onElaborate(subject) }
                    .buttonStyle(SmallPillButtonStyle())
                    .help(loc("Un texte plus long de Claude, à la place des notes",
                              en: "A longer text from Claude, in place of the notes"))
            }
            searchInClaude
        }
        .fixedSize()
    }

    /// Claude in the browser, where he searches the web: one button when
    /// the card knows one subject, a menu when it knows the two.
    @ViewBuilder
    private var searchInClaude: some View {
        let subjects = session.subjects
        if subjects.count == 1, let only = subjects.first {
            Button(Self.searchTitle) { onSearch(only) }
                .buttonStyle(SmallPillButtonStyle())
                .help(Self.searchHelp)
        } else if subjects.count > 1 {
            Menu {
                ForEach(subjects, id: \.self) { subject in
                    Button(subject.searchTitle) { onSearch(subject) }
                }
            } label: {
                // The ellipsis says a choice comes first, as macOS has it.
                Text(Self.searchTitle + "…")
            }
            .menuStyle(.button)
            .buttonStyle(SmallPillButtonStyle())
            .help(Self.searchHelp)
        }
    }

    static var searchTitle: String { loc("Chercher dans Claude", en: "Search in Claude") }
    static var searchHelp: String {
        loc("Ouvre claude.ai avec la demande préremplie : Claude cherche sur le web avant de répondre",
            en: "Opens claude.ai with the request filled in: Claude searches the web before answering")
    }

    /// The title, the artist, then where the track comes from — the album
    /// and the app playing it.
    private func trackText(_ track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(track.title)
                    .font(.system(size: textSize.points(14), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                if !track.isPlaying {
                    StatusPill {
                        Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold))
                        Text(loc("en pause", en: "paused"))
                    }
                    .fixedSize()
                }
            }
            if let artist = track.artist {
                Text(artist)
                    .font(.system(size: textSize.bodyPoints))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let origin = origin(of: track) {
                Text(origin)
                    .font(.system(size: textSize.points(11)))
                    .foregroundStyle(.secondary)
            }
            if let facts = session.facts?.summary(playerAlbum: track.album, english: AppSettings.language.showsEnglish) {
                // What MusicBrainz said, when it has: the album of origin
                // if the player plays a compilation, the year, the type.
                Text(facts)
                    .font(.system(size: textSize.points(11)))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: session.facts == nil)
        .lineLimit(2)
        // A title on two lines is a sentence to read, not a label to cut.
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Album · app", with whichever of the two the player gave.
    private func origin(of track: NowPlayingTrack) -> String? {
        let parts = [track.album, track.appName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Claude's notes: a caret while they come in, plain text once done.
    /// Three sentences fit; a longer answer scrolls past the panel's usual
    /// ceiling rather than pushing it off the screen.
    private var notes: some View {
        ScrollView {
            notesText
                .font(.system(size: textSize.bodyPoints))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ListeningNotesHeightKey.self, value: geo.size.height)
                    }
                }
        }
        .frame(height: min(notesHeight, textSize.maxTextHeight))
        .onPreferenceChange(ListeningNotesHeightKey.self) { height in
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

    @ViewBuilder private var notesText: some View {
        if session.phase == .streaming {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let caretOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                Text(shownText)
                    + Text("▍").foregroundStyle(caretOn ? ClaudioTheme.accent : .clear)
            }
        } else {
            Text(shownText)
        }
    }

    private func messageView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.system(size: textSize.points(13), weight: .semibold))
            Text(detail)
                .font(.system(size: textSize.points(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // An error is a sentence, not a label: without this it is
                // cut off at one line, right where it says what went wrong.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        // Under a card, the card already makes room above.
        .padding(.top, session.track == nil ? 26 : 14)
        .padding(.bottom, 22)
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
            Text(loc("Échap pour fermer", en: "esc to close")).font(.caption2).foregroundStyle(.tertiary)
            if showsModelName {
                // Neither the separator nor the model name are translated.
                Text(verbatim: "·").font(.caption2).foregroundStyle(.quaternary)
                Text(session.model.shortName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            // Under the long text: the same subject, in Claude's browser. The
            // footer is narrow: the site's name says where it goes.
            if let subject = session.essaySubject, session.phase != .missingKey {
                Button("claude.ai") { onSearch(subject) }
                    .buttonStyle(PanelPillButtonStyle())
                    .help(Self.searchHelp)
            }
            // The way back to the notes, when there are notes to go back to.
            if session.essaySubject != nil, !session.cameFromLink {
                Button(loc("Retour", en: "Back"), action: onBack)
                    .buttonStyle(PanelPillButtonStyle())
            }
            switch session.phase {
            case .missingKey:
                Button(loc("Réglages…", en: "Settings…"), action: onOpenSettings)
                    .buttonStyle(PanelPillButtonStyle())
            case .error:
                Button(loc("Réessayer", en: "Try again"), action: onRetry)
                    .buttonStyle(PanelPillButtonStyle())
            case .reading, .nothing, .streaming, .done:
                EmptyView()
            }
            // Always last, whatever the phase: it copies the card, and ⌘C
            // works as soon as the card is up.
            if session.track != nil {
                Button(action: onCopy) {
                    if session.justCopied {
                        Text(loc("Copié ✓", en: "Copied ✓"))
                    } else {
                        Text(loc("Copier ", en: "Copy ")) + Text("⌘C").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PanelPillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Ideal height of the whole panel, reported to the window so it hugs its
/// content.
private struct ListeningPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the notes inside their ScrollView, to bound it.
private struct ListeningNotesHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
