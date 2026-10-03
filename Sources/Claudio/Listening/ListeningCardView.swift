import SwiftUI

/// The track as its player names it, then the way to it in Galette when
/// this Mac has Galette, from the moment the card is up; then the ways to
/// Claude. The top of the "What's playing?" panel, above the notes.
struct ListeningCardView: View {
    @ObservedObject var session: ListeningSession
    let track: NowPlayingTrack
    let textSize: PanelTextSize
    let actions: ListeningPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let artwork = session.artwork {
                    cover(artwork)
                }
                trackText
            }
            .animation(.easeOut(duration: 0.18), value: session.artwork == nil)
            // Two rows: the ways to Galette, then the ways to Claude. Side
            // by side, the three subjects and the search overflowed the card.
            if let buttons = GaletteButtons(galette: session.galette, links: session.galetteLinks,
                                            onOpen: actions.openInGalette) {
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
                Button(subject.buttonTitle) { actions.elaborate(subject) }
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
            Button(Self.searchTitle) { actions.search(only) }
                .buttonStyle(SmallPillButtonStyle())
                .help(Self.searchHelp)
        } else if subjects.count > 1 {
            Menu {
                ForEach(subjects, id: \.self) { subject in
                    Button(subject.searchTitle) { actions.search(subject) }
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

    /// The title, the artist, then where the track comes from: the album
    /// and the app playing it.
    private var trackText: some View {
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
            if let origin {
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
    private var origin: String? {
        let parts = [track.album, track.appName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
