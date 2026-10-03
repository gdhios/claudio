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

    /// The model writing what is on screen, for the panel's footer: the
    /// notes' while the notes show, the long text's while it does.
    @Published private(set) var model: ModelChoice
    /// The model the notes come from.
    let notesModel: ModelChoice

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
    /// "Tell me more": the subject the long text is about, while it is on
    /// screen in place of the notes. `nil` shows the notes.
    @Published var essaySubject: MusicSubject?
    /// The long text, as it streams.
    @Published var essay = ""
    /// What MusicBrainz said of the subject's artist before the long text:
    /// shown nowhere, carried by the "Search in Claude" link.
    @Published var artistFacts: ArtistFacts?
    /// Opened by a `claudio://music` link: there are no notes to go back
    /// to, the panel only closes.
    var cameFromLink = false
    /// Claude's notes, as they stream. Three sentences at most: published as
    /// they come, with no buffering to spare the layout.
    @Published var notes = ""
    @Published var justCopied = false
    /// Galette, when the panel found it as it opened: the card then offers to
    /// open the track in it. `nil` without Galette.
    @Published var galette: GaletteApp?

    init(model: ModelChoice = ListeningNotes.model) {
        self.model = model
        notesModel = model
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

    /// The long text is being asked for, from its own model: whatever an
    /// earlier one said goes.
    func beginEssay(on subject: MusicSubject, model: ModelChoice) {
        essaySubject = subject
        essay = ""
        artistFacts = nil
        self.model = model
        phase = .streaming
    }

    func appendEssay(_ piece: String) { essay += piece }

    func finishEssay(with text: String) {
        essay = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .done
    }

    /// Back to the notes, as they were, and to their model in the footer.
    func closeEssay() {
        essaySubject = nil
        essay = ""
        model = notesModel
        phase = .done
    }

    /// The pills that lead to the long text: the track, its album and its
    /// artist, while the notes are what's on screen.
    var subjects: [MusicSubject] {
        guard essaySubject == nil, let track else { return [] }
        return [MusicSubject.track(of: track, facts: facts),
                MusicSubject.album(of: track, facts: facts),
                MusicSubject.artist(of: track, facts: facts)].compactMap { $0 }
    }

    /// The whole answer replaces what streamed on the way.
    func finish(with text: String) {
        notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .done
    }
}
