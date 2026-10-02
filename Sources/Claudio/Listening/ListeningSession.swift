import SwiftUI

/// One "What's playing?", from the player being read to Claude's last word.
/// Observable like the other sessions, and all the panel reads: the
/// coordinator only ever moves it forward.
@MainActor
final class ListeningSession: ObservableObject {
    enum Phase: Equatable {
        /// The player is being asked what it plays.
        case reading
        /// It plays nothing. The panel says so, then closes itself.
        case nothing
        /// The card is up and Claude's notes are coming in under it.
        case streaming
        case done
        /// No Claude key: the card stays, with the way to Settings under it.
        case missingKey
        /// Claude failed. The card stays, with the reason and a retry.
        case error(String)
    }

    /// What the menu, Settings and the palette call the action.
    static var menuTitle: String { loc("Qu'est-ce que j'écoute ?", en: "What's playing?") }
    /// What the panel's header calls it: the name of the macOS widget it reads.
    static var panelTitle: String { loc("À l'écoute", en: "Now playing") }
    /// The palette row's second line: what it does, in one breath.
    static var paletteDetail: String {
        loc("Le morceau en cours, raconté par Claude", en: "The track playing, told by Claude")
    }
    /// Never shown: the words the palette also finds the row by, those
    /// someone after the track would type and its labels don't hold.
    static var searchTerms: String {
        loc("musique chanson titre artiste album son", en: "music song title artist album listening")
    }

    /// The model the notes come from, for the panel's footer.
    let model: ModelChoice

    @Published var phase: Phase = .reading
    /// The track as the player described it, `nil` until it has been read —
    /// and when it plays nothing.
    @Published var track: NowPlayingTrack?
    /// The track's cover, when its player gave one: it arrives on its own,
    /// after the card and whatever Claude is doing.
    @Published var artwork: NSImage?
    /// What MusicBrainz said of the track, when it was asked and answered
    /// in time: known at once from the cache, or arriving on its own.
    @Published var facts: TrackFacts?
    /// Claude's notes, as they stream. Three sentences at most: published as
    /// they come, with no buffering to spare the layout.
    @Published var notes = ""
    @Published var justCopied = false
    /// Galette, when the panel found it as it opened: the card then offers to
    /// open the track in it. `nil` without Galette.
    @Published var galette: GaletteApp?

    init(model: ModelChoice = ListeningNotes.model) {
        self.model = model
    }

    /// The card's Galette buttons, in order: none without Galette, before
    /// the track is read, or for a track that gives nothing to open.
    var galetteLinks: [GaletteLink] {
        guard let galette, let track else { return [] }
        return galette.links(for: track)
    }

    /// Claude is being asked: whatever an earlier attempt wrote goes.
    func beginStreaming() {
        notes = ""
        phase = .streaming
    }

    func appendNotes(_ piece: String) { notes += piece }

    /// The whole answer replaces what streamed on the way.
    func finish(with text: String) {
        notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .done
    }
}
