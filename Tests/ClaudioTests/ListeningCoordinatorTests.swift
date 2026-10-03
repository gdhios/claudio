import AppKit
import Combine
import XCTest
@testable import Claudio

/// "What's playing?", from the shortcut to Claude's last word — with no
/// player, no `osascript`, no network and no window. The source answers a
/// fixed track (or holds its answer until told to), the model is a fake
/// client, and the panel is never built: the bench only counts how many
/// were asked for.
@MainActor
final class ListeningCoordinatorTests: XCTestCase {

    /// Nothing playing: the panel says so, and takes itself off the screen
    /// after the same beat as "No selection found" — without asking Claude
    /// anything, since there is nothing to ask about.
    func testNothingPlayingSaysSoThenClosesAfterTheDelay() async throws {
        let bench = Bench(track: nil)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        XCTAssertEqual(bench.panels, 1)

        await bench.runs()
        XCTAssertEqual(session.phase, .nothing)
        XCTAssertNil(session.track)
        XCTAssertEqual(bench.clientRequests, [])
        // Said first, closed after: a glance is still a glance.
        XCTAssertNotNil(bench.coordinator.session)

        await bench.wait { bench.coordinator.session == nil }
        XCTAssertNil(bench.coordinator.session)
    }

    /// The whole point: the card goes up as soon as the track is read, and
    /// Claude's notes stream in underneath it, from Sonnet, on the fixed
    /// budget. Done, the panel stays until Esc.
    func testATrackShowsItsCardThenStreamsTheNotes() async throws {
        let bench = Bench()
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        let log = bench.watch(session)

        await bench.runs()
        XCTAssertEqual(log.phases, [.reading, .streaming, .done])
        XCTAssertEqual(bench.cardWhenClaudeWasAsked, [.sample])
        XCTAssertTrue(log.notes.contains(String(Bench.notes.prefix(Bench.notes.count / 2))),
                      "the notes should arrive piece by piece: \(log.notes)")
        XCTAssertEqual(session.notes, Bench.notes)

        XCTAssertEqual(bench.clientRequests, [.claude(.sonnet55)])
        XCTAssertEqual(bench.client.texts, [ListeningNotes.userMessage(for: .sample)])
        XCTAssertEqual(bench.client.systems, [ListeningNotes.system()])
        XCTAssertEqual(bench.client.budgets, [400])
        XCTAssertNotNil(bench.coordinator.session)
    }

    /// The model is a setting since the Models tab: the coordinator asks
    /// for whatever it says, and the session names it for the footer.
    func testTheNotesComeFromTheModelSetInSettings() async throws {
        let bench = Bench(model: .claude(.haiku45))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        XCTAssertEqual(session.model, .claude(.haiku45))

        await bench.runs()
        XCTAssertEqual(bench.clientRequests, [.claude(.haiku45)])
    }

    /// Without a key the card is still worth something: it stays, with the
    /// usual missing-key message under it.
    func testWithoutAKeyTheCardStaysWithTheMissingKeyMessage() async throws {
        let bench = Bench(hasClient: false)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.phase, .missingKey)
        XCTAssertEqual(session.track, .sample)
        XCTAssertEqual(bench.clientRequests, [.claude(.sonnet55)])
        XCTAssertEqual(bench.client.calls, 0)
        XCTAssertNotNil(bench.coordinator.session)
    }

    /// Claude failing takes nothing away from what the player said: the
    /// card stays, the error goes under it.
    func testAClientErrorKeepsTheCard() async throws {
        let bench = Bench(answer: .failure(ModelFailure()))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.phase, .error(ModelFailure().localizedDescription))
        XCTAssertEqual(session.track, .sample)
        XCTAssertEqual(bench.client.calls, 1)
        XCTAssertNotNil(bench.coordinator.session)
    }

    /// Nothing is an answer too, and a wrong one: the card stays, and under
    /// it the panel says the stream ended with nothing, how, and offers
    /// "Try again" — rather than "Ready" over a blank.
    func testAnEmptyAnswerIsAnErrorThatSaysHow() async throws {
        let bench = Bench(answer: .success("  \n"), stopReason: "end_turn", blockTypes: ["text"])
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        guard case .error(let message) = session.phase else { return XCTFail("\(session.phase)") }
        XCTAssertTrue(message.contains("end_turn · text · 0 jetons"), message)
        XCTAssertTrue(message.contains(ListeningNotes.model.shortName), message)
        XCTAssertEqual(session.track, .sample)
    }

    /// Esc while the player is still being read: the panel goes, and the
    /// answer that comes afterwards neither brings it back nor asks Claude
    /// anything.
    func testEscapeWhileReadingLeavesNeitherPanelNorCall() async throws {
        let bench = Bench(readsWait: true)
        bench.coordinator.trigger()
        let cycle = try XCTUnwrap(bench.coordinator.cycle)
        await bench.settle { bench.reads == 1 }

        bench.coordinator.dismiss()
        bench.answerRead()
        await cycle.value
        XCTAssertNil(bench.coordinator.session)
        XCTAssertEqual(bench.panels, 1)
        XCTAssertEqual(bench.clientRequests, [])
        XCTAssertEqual(bench.client.calls, 0)
    }

    // MARK: - The facts

    /// MusicBrainz is asked beside the card and never waited for: Claude is
    /// asked without the facts, they take their place under the card when
    /// they arrive, and the card's player cover is left alone.
    func testTheFactsArriveOnTheirOwnUnderTheCard() async throws {
        let bench = Bench(artwork: Bench.cover, facts: Bench.facts, factsWait: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(bench.factsRequests, [.sample])
        XCTAssertNil(session.facts, "the notes never wait for the facts")
        XCTAssertEqual(bench.client.texts, [ListeningNotes.userMessage(for: .sample)])

        bench.answerFacts()
        await bench.wait { session.facts != nil }
        XCTAssertEqual(session.facts, Bench.facts)
        XCTAssertEqual(bench.remoteCoverRequests, [], "the player gave a cover: the archive isn't asked")
    }

    /// Facts already in the cache go to Claude with the first request, and
    /// MusicBrainz isn't asked again.
    func testCachedFactsGoToClaudeAtOnce() async throws {
        let bench = Bench(cachedFacts: Bench.facts, facts: Bench.facts)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.facts, Bench.facts)
        XCTAssertEqual(bench.client.texts, [ListeningNotes.userMessage(for: .sample, facts: Bench.facts)])
        XCTAssertEqual(bench.factsRequests, [])
    }

    /// No cover from the player: the archive's, by the release group the
    /// facts name, once they are in.
    func testWithoutAPlayerCoverTheArchivesIsFetched() async throws {
        let bench = Bench(artwork: nil, facts: Bench.facts, remoteCover: Bench.cover)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        await bench.wait { session.artwork != nil }
        XCTAssertEqual(bench.remoteCoverRequests, [Bench.facts])
        XCTAssertTrue(session.artwork === Bench.cover)
    }

    /// MusicBrainz switched off: nothing is asked of it, nor of the archive.
    func testWithMusicBrainzOffNothingIsAsked() async throws {
        let bench = Bench(artwork: nil, cachedFacts: Bench.facts, facts: Bench.facts, remoteCover: Bench.cover,
                          preferences: .init(musicBrainz: false, showsArtwork: true, detail: .threeSentences))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertNil(session.facts)
        XCTAssertEqual(bench.factsRequests, [])
        XCTAssertEqual(bench.remoteCoverRequests, [])
        XCTAssertEqual(bench.client.texts, [ListeningNotes.userMessage(for: .sample)])
    }

    /// The cover switched off: neither the player's nor the archive's is
    /// asked for, facts or not.
    func testWithTheCoverOffNoCoverIsAskedFor() async throws {
        let bench = Bench(artwork: Bench.cover, cachedFacts: Bench.facts, remoteCover: Bench.cover,
                          preferences: .init(musicBrainz: true, showsArtwork: false, detail: .threeSentences))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(session.artwork)
        XCTAssertEqual(bench.artworkRequests, [])
        XCTAssertEqual(bench.remoteCoverRequests, [])
    }

    /// The detail setting is the budget Claude gets and the ask in the prompt.
    func testTheDetailSettingReachesClaude() async throws {
        let bench = Bench(preferences: .init(musicBrainz: true, showsArtwork: true, detail: .oneSentence))
        bench.coordinator.trigger()
        await bench.runs()
        XCTAssertEqual(bench.client.budgets, [150])
        XCTAssertEqual(bench.client.systems, [ListeningNotes.system(detail: .oneSentence)])
    }

    // MARK: - "Try again" on another track

    /// The player moved on between the failure and "Try again": the facts
    /// still coming for the old track belong to a card that is gone, and
    /// never land on the new one.
    func testARetryOnAnotherTrackDropsTheOldTracksFacts() async throws {
        let bench = Bench(answer: .failure(ModelFailure()), facts: Bench.facts, factsWait: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        await bench.settle { bench.factsRequests.count == 1 }

        bench.track = .other
        bench.cachedFacts = Bench.otherFacts
        bench.coordinator.retry()
        await bench.runs()
        XCTAssertEqual(session.facts, Bench.otherFacts)

        bench.answerFacts()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.facts, Bench.otherFacts, "the old track's facts land nowhere")
    }

    /// Same for the archive's cover of the old track: the new card, which
    /// has none, stays without.
    func testARetryOnAnotherTrackDropsTheOldTracksArchiveCover() async throws {
        let bench = Bench(answer: .failure(ModelFailure()), facts: Bench.facts,
                          remoteCover: Bench.cover, remoteCoverWaits: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        await bench.settle { bench.remoteCoverRequests.count == 1 }
        XCTAssertEqual(bench.remoteCoverRequests, [Bench.facts])

        bench.track = .other
        bench.cachedFacts = Bench.otherFacts  // no release group: no cover of its own
        bench.coordinator.retry()
        await bench.runs()

        bench.answerRemoteCover()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(session.artwork, "the old track's cover lands nowhere")
    }

    /// Paused since the failure, it is still the same track: "Try again"
    /// keeps its cover on the card rather than blink, and the card says
    /// it's paused.
    func testARetryOnThePausedTrackKeepsItsCover() async throws {
        let bench = Bench(answer: .failure(ModelFailure()), artwork: Bench.cover)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        await bench.wait { session.artwork != nil }

        var paused = NowPlayingTrack.sample
        paused.isPlaying = false
        bench.track = paused
        bench.artworkWaits = true  // the cover asked again is still on its way
        bench.coordinator.retry()
        await bench.runs()
        XCTAssertEqual(session.track?.isPlaying, false)
        XCTAssertTrue(session.artwork === Bench.cover, "the same track keeps its cover")
    }

    // MARK: - "Tell me more"

    /// A pill on the card: the notes make way for a long text about the
    /// album, from the same model with the essay's prompt and budget; the
    /// facts in hand go with the subject. "Back" brings the notes back.
    func testTellMeMoreStreamsALongTextOverTheNotesThenComesBack() async throws {
        let bench = Bench(cachedFacts: Bench.facts)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        let subject = try XCTUnwrap(MusicSubject.album(of: .sample, facts: Bench.facts))
        bench.coordinator.elaborate(on: subject)
        XCTAssertEqual(session.essaySubject, subject)
        XCTAssertEqual(session.phase, .streaming)
        await bench.runs()
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.essay, Bench.notes)
        XCTAssertEqual(session.notes, Bench.notes, "the notes are kept for the way back")
        XCTAssertEqual(bench.client.texts.last, ListeningEssay.userMessage(for: subject))
        XCTAssertEqual(bench.client.systems.last, ListeningEssay.system())
        XCTAssertEqual(bench.client.budgets.last, ListeningEssay.maxTokens)
        XCTAssertEqual(bench.clientRequests, [ListeningNotes.model, ListeningEssay.model])
        XCTAssertEqual(bench.artistRequests, [subject], "the artist's facts were asked for, and were none")

        bench.coordinator.back()
        XCTAssertNil(session.essaySubject)
        XCTAssertEqual(session.essay, "")
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.notes, Bench.notes)
    }

    /// The long text has its own model: Haiku on the notes, the text's own
    /// on the text, and the footer follows what is on screen.
    func testTheLongTextComesFromItsOwnModel() async throws {
        let bench = Bench(model: .claude(.haiku45), essayModel: .claude(.opus55))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(session.model, .claude(.haiku45))

        bench.coordinator.elaborate(on: try XCTUnwrap(MusicSubject.artist(of: .sample)))
        XCTAssertEqual(session.model, .claude(.opus55), "the footer names the model writing")
        await bench.runs()
        XCTAssertEqual(bench.clientRequests, [.claude(.haiku45), .claude(.opus55)])

        bench.coordinator.back()
        XCTAssertEqual(session.model, .claude(.haiku45))
    }

    /// Before the long text, the artist's facts are fetched — the text
    /// waits for them — and go to Claude after the subject. The panel
    /// streams meanwhile: the wait shows as the text coming.
    func testTheArtistsFactsAreFetchedBeforeTheLongText() async throws {
        let bench = Bench(artistFacts: Bench.artist, artistWaits: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        let subject = try XCTUnwrap(MusicSubject.artist(of: .sample))
        bench.coordinator.elaborate(on: subject)
        await bench.wait { bench.artistRequests == [subject] }
        XCTAssertEqual(session.phase, .streaming)
        XCTAssertEqual(bench.client.texts.count, 1, "Claude isn't asked before the facts are in")

        bench.answerArtist()
        await bench.runs()
        XCTAssertEqual(bench.client.texts.last, ListeningEssay.userMessage(for: subject, artist: Bench.artist))
        XCTAssertEqual(session.essay, Bench.notes)
    }

    /// "Open Spotify": the player comes forward, and the panel closes, the
    /// listener gone back to it. Without a player there is nothing to open.
    func testOpenPlayerBringsThePlayerForwardThenClosesThePanel() async throws {
        let bench = Bench()
        bench.coordinator.trigger()
        await bench.runs()

        bench.coordinator.openPlayer()
        XCTAssertEqual(bench.activated, ["com.spotify.client"])
        XCTAssertNil(bench.coordinator.session)

        let linked = Bench(track: NowPlayingTrack(title: "LOVE TRIP", artist: "間宮貴子", appName: "Galette"))
        linked.coordinator.trigger()
        await linked.runs()
        linked.coordinator.openPlayer()
        XCTAssertEqual(linked.activated, [])
        XCTAssertNotNil(linked.coordinator.session)
    }

    /// "Search in Claude" from the card: the browser opens on claude.ai
    /// with the subject, and the panel closes, its job done. After the
    /// long text, the artist's facts go along.
    func testSearchInClaudeOpensTheLinkThenClosesThePanel() async throws {
        let bench = Bench(artistFacts: Bench.artist)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        let subject = try XCTUnwrap(MusicSubject.artist(of: .sample))

        bench.coordinator.search(subject)
        XCTAssertEqual(bench.opened, [ClaudeSearch.url(for: subject, artist: nil, language: AppSettings.language, desktop: false)])
        XCTAssertNil(bench.coordinator.session)

        bench.coordinator.trigger()
        let again = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        bench.coordinator.elaborate(on: subject)
        await bench.runs()
        XCTAssertEqual(again.artistFacts, Bench.artist, "kept for the link, and shown nowhere")
        bench.coordinator.search(subject)
        XCTAssertEqual(bench.opened.last, ClaudeSearch.url(for: subject, artist: Bench.artist, language: AppSettings.language, desktop: false))
        _ = session
    }

    /// With Claude Desktop on the Mac, the link takes its scheme.
    func testWithClaudeDesktopTheLinkTakesItsScheme() async throws {
        let bench = Bench(claudeDesktop: true)
        bench.coordinator.trigger()
        await bench.runs()
        let subject = try XCTUnwrap(MusicSubject.artist(of: .sample))
        bench.coordinator.search(subject)
        XCTAssertEqual(bench.opened.first?.scheme, "claude")
    }

    /// MusicBrainz off: no facts are asked for, the text goes at once.
    func testWithMusicBrainzOffTheLongTextAsksNoFacts() async throws {
        let bench = Bench(artistFacts: Bench.artist,
                          preferences: .init(musicBrainz: false, showsArtwork: true, detail: .threeSentences))
        bench.coordinator.trigger()
        await bench.runs()
        let subject = try XCTUnwrap(MusicSubject.artist(of: .sample))
        bench.coordinator.elaborate(on: subject)
        await bench.runs()
        XCTAssertEqual(bench.artistRequests, [])
        XCTAssertEqual(bench.client.texts.last, ListeningEssay.userMessage(for: subject))
    }

    /// A `claudio://music` link from Galette: the panel opens on the
    /// subject's card, nothing is read from the player, the text streams
    /// at once, and the archive is asked for the album's cover.
    func testALinkOpensOnTheSubjectAndStreamsWithoutReadingThePlayer() async throws {
        let bench = Bench(remoteCover: Bench.cover)
        let subject = MusicSubject(kind: .album, artist: "間宮貴子", title: "LOVE TRIP",
                                   mbid: "3b03f2df-1fc0", firstReleaseDate: "1982-11-25", type: "Album")
        bench.coordinator.open(subject)
        let session = try XCTUnwrap(bench.coordinator.session)
        XCTAssertEqual(bench.panels, 1)
        XCTAssertEqual(session.track, subject.card)
        XCTAssertEqual(session.essaySubject, subject)
        XCTAssertTrue(session.cameFromLink)

        await bench.runs()
        XCTAssertEqual(bench.reads, 0)
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.essay, Bench.notes)
        XCTAssertEqual(bench.client.texts, [ListeningEssay.userMessage(for: subject)])
        XCTAssertEqual(bench.factsRequests, [], "the link brought its facts")
        XCTAssertEqual(bench.artistRequests, [subject], "the artist is still asked about")
        XCTAssertEqual(session.model, ListeningEssay.model)
        await bench.wait { session.artwork != nil }
        XCTAssertEqual(bench.remoteCoverRequests.map(\.releaseGroupID), ["3b03f2df-1fc0"])
        XCTAssertEqual(session.facts?.summary(playerAlbum: "LOVE TRIP", english: false), "1982 · album")
    }

    // MARK: - The cover

    /// The cover is the player's own, read beside the card and never
    /// waited for: Claude is asked and answers while it is still coming,
    /// and it takes its place on the card when it arrives.
    func testTheCoverArrivesOnItsOwnBesideTheCard() async throws {
        let bench = Bench(artwork: Bench.cover, artworkWaits: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(bench.artworkRequests, [.sample])
        XCTAssertNil(session.artwork, "the notes never wait for the cover")

        bench.answerArtwork()
        await bench.wait { session.artwork != nil }
        XCTAssertTrue(session.artwork === Bench.cover)
    }

    /// Nothing playing: no track, so no cover to ask for.
    func testNothingPlayingAsksForNoCover() async throws {
        let bench = Bench(track: nil, artwork: Bench.cover)
        bench.coordinator.trigger()
        await bench.runs()
        XCTAssertEqual(bench.artworkRequests, [])
    }

    /// Esc while the cover is still coming: it belongs to a panel that is
    /// gone, and lands nowhere.
    func testEscapeWhileTheCoverIsComingDropsIt() async throws {
        let bench = Bench(artwork: Bench.cover, artworkWaits: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        bench.coordinator.dismiss()
        bench.answerArtwork()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(session.artwork)
        XCTAssertNil(bench.coordinator.session)
    }

    // MARK: - Galette

    /// With Galette on the Mac, the card offers the artist, then the album.
    /// Galette is looked for once, as the panel opens.
    func testWithGaletteTheCardOffersTheArtistThenTheAlbum() async throws {
        let bench = Bench(galetteInstalled: true)
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)
        XCTAssertEqual(bench.galette.lookups, 1)

        await bench.runs()
        XCTAssertEqual(session.galetteLinks, [.artist(name: "間宮貴子"),
                                              .album(artist: "間宮貴子", title: "LOVE TRIP")])
        XCTAssertEqual(bench.galette.lookups, 1)
    }

    /// Without Galette, no button — and nothing on the card says it's missing.
    func testWithoutGaletteTheCardOffersNothing() async throws {
        let bench = Bench()
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.track, .sample)
        XCTAssertNil(session.galette)
        XCTAssertEqual(session.galetteLinks, [])
    }

    /// A button hands its link to Galette, and the panel, its job done,
    /// closes.
    func testAGaletteButtonOpensItsLinkThenClosesThePanel() async throws {
        let bench = Bench(galetteInstalled: true)
        bench.coordinator.trigger()
        await bench.runs()

        let album = GaletteLink.album(artist: "間宮貴子", title: "LOVE TRIP")
        bench.coordinator.openInGalette(album)
        XCTAssertEqual(bench.galette.opened, [album.url])
        XCTAssertNil(bench.coordinator.session)
    }
}

// MARK: - The bench

private extension NowPlayingTrack {
    static let sample = NowPlayingTrack(title: "真夜中のジョーク",
                                        artist: "間宮貴子",
                                        album: "LOVE TRIP",
                                        appName: "Spotify",
                                        bundleID: "com.spotify.client",
                                        isPlaying: true)
    /// What the player plays by the time "Try again" reads it again.
    static let other = NowPlayingTrack(title: "Plastic Love",
                                       artist: "竹内まりや",
                                       album: "VARIETY",
                                       appName: "Spotify",
                                       bundleID: "com.spotify.client")
}

/// One coordinator and the fakes it was built with.
@MainActor
private final class Bench: AsyncWaiting {
    static let notes = "Takako Mamiya est une chanteuse japonaise de city pop. Love Trip est son seul album."
    /// The cover the fake player hands back, compared by identity.
    static let cover = NSImage(size: NSSize(width: 1, height: 1))
    static let facts = TrackFacts(recordingID: "783dfef9", releaseGroupID: "3b03f2df", albumTitle: "LOVE TRIP",
                                  primaryType: "Album", secondaryTypes: [], firstReleaseDate: "1982-11-25")
    /// `NowPlayingTrack.other`'s, from Deezer: no release group to ask the
    /// archive a cover for.
    static let otherFacts = TrackFacts(recordingID: "", releaseGroupID: nil, albumTitle: "VARIETY",
                                       primaryType: "Album", secondaryTypes: [], firstReleaseDate: "1984-04-25",
                                       origin: .deezer)
    static let artist = ArtistFacts(artistID: "c3a2c5d6", name: "間宮貴子", type: "Person", country: "JP",
                                    beginDate: nil, releases: [
                                        ArtistFacts.Release(id: "3b03f2df", title: "LOVE TRIP", primaryType: "Album",
                                                            secondaryTypes: [], firstReleaseDate: "1982-11-25")])

    let client: FakeTextStreamClient
    /// Galette, missing unless the test installs it.
    let galette: FakeGalette
    var coordinator: ListeningCoordinator { built }
    private var built: ListeningCoordinator!

    /// What the player says is playing, `nil` for nothing. Read at each
    /// read: a test changes it to have the player move on.
    var track: NowPlayingTrack?
    /// What the cache already knows, whatever the track; changed by a test
    /// along with the track.
    var cachedFacts: TrackFacts?
    /// Reads wait for `answerRead()` instead of answering at once: that's
    /// the player still being read when Esc comes.
    let readsWait: Bool
    /// How many times the player was read.
    private(set) var reads = 0
    /// Every model a client was asked for: empty proves nothing was asked.
    private(set) var clientRequests: [ModelChoice] = []
    /// The card on the panel each time a client was asked for: the track
    /// has to be on screen before Claude is asked about it.
    private(set) var cardWhenClaudeWasAsked: [NowPlayingTrack?] = []
    /// How many panels were put on screen.
    private(set) var panels = 0
    /// Every track a cover was asked for.
    private(set) var artworkRequests: [NowPlayingTrack] = []
    /// Every track MusicBrainz was asked about.
    private(set) var factsRequests: [NowPlayingTrack] = []
    /// Every facts the archive was asked a cover for.
    private(set) var remoteCoverRequests: [TrackFacts] = []
    /// Every subject MusicBrainz was asked the artist of.
    private(set) var artistRequests: [MusicSubject] = []
    /// Every link handed to the browser.
    private(set) var opened: [URL] = []
    /// Every player brought forward, by bundle id.
    private(set) var activated: [String] = []
    private var waitingFacts: [CheckedContinuation<TrackFacts?, Never>] = []
    private var waitingArtists: [CheckedContinuation<ArtistFacts?, Never>] = []

    private var waitingReads: [CheckedContinuation<NowPlayingTrack?, Never>] = []
    private var waitingArtwork: [CheckedContinuation<NSImage?, Never>] = []
    private var waitingRemoteCovers: [CheckedContinuation<NSImage?, Never>] = []
    private let artwork: NSImage?
    /// Covers wait for `answerArtwork()`; read at each request.
    var artworkWaits: Bool
    private let remoteCover: NSImage?

    init(track: NowPlayingTrack? = .sample,
         answer: Result<String, Error> = .success(Bench.notes),
         hasClient: Bool = true,
         readsWait: Bool = false,
         galetteInstalled: Bool = false,
         artwork: NSImage? = nil,
         artworkWaits: Bool = false,
         cachedFacts: TrackFacts? = nil,
         facts: TrackFacts? = nil,
         factsWait: Bool = false,
         remoteCover: NSImage? = nil,
         remoteCoverWaits: Bool = false,
         artistFacts: ArtistFacts? = nil,
         artistWaits: Bool = false,
         claudeDesktop: Bool = false,
         preferences: ListeningPreferences = .init(musicBrainz: true, showsArtwork: true, detail: .threeSentences),
         model: ModelChoice = ListeningNotes.model,
         essayModel: ModelChoice = ListeningEssay.model,
         stopReason: String? = "end_turn",
         blockTypes: [String] = ["text"]) {
        self.track = track
        self.cachedFacts = cachedFacts
        self.readsWait = readsWait
        self.artwork = artwork
        self.artworkWaits = artworkWaits
        self.remoteCover = remoteCover
        let client = FakeTextStreamClient(answer)
        client.stopReason = stopReason
        client.blockTypes = blockTypes
        self.client = client
        galette = FakeGalette(installed: galetteInstalled)
        built = ListeningCoordinator(
            source: NowPlayingSource { [weak self] in
                guard let self else { return nil }
                reads += 1
                guard readsWait else { return self.track }
                return await withCheckedContinuation { waitingReads.append($0) }
            },
            client: { [weak self] choice in
                self?.clientRequests.append(choice)
                self?.cardWhenClaudeWasAsked.append(self?.coordinator.session?.track)
                return hasClient ? client : nil
            },
            panel: { [weak self] _, _ in
                self?.panels += 1
                return nil
            },
            durations: .init(empty: .milliseconds(50), failure: .milliseconds(50)),
            galette: galette.service,
            artwork: ArtworkSource { [weak self] track in
                guard let self else { return nil }
                artworkRequests.append(track)
                guard self.artworkWaits else { return artwork }
                return await withCheckedContinuation { waitingArtwork.append($0) }
            },
            facts: FactsSource(
                cached: { [weak self] _ in self?.cachedFacts },
                fetch: { [weak self] track in
                    guard let self else { return nil }
                    factsRequests.append(track)
                    guard factsWait else { return facts }
                    return await withCheckedContinuation { waitingFacts.append($0) }
                },
                artist: { [weak self] subject in
                    guard let self else { return nil }
                    artistRequests.append(subject)
                    guard artistWaits else { return artistFacts }
                    return await withCheckedContinuation { waitingArtists.append($0) }
                }
            ),
            remoteArtwork: RemoteArtworkSource { [weak self] facts in
                guard let self else { return nil }
                remoteCoverRequests.append(facts)
                guard remoteCoverWaits else { return remoteCover }
                return await withCheckedContinuation { waitingRemoteCovers.append($0) }
            },
            preferences: { preferences },
            model: { model },
            essayModel: { essayModel },
            openLink: { [weak self] url in self?.opened.append(url) },
            claudeDesktop: { claudeDesktop },
            activatePlayer: { [weak self] bundleID in self?.activated.append(bundleID) }
        )
    }

    /// Hands the artist's facts to every request still waiting.
    func answerArtist() {
        let waiting = waitingArtists
        waitingArtists = []
        for request in waiting { request.resume(returning: Bench.artist) }
    }

    /// Hands the facts to every request still waiting, as MusicBrainz
    /// finally does.
    func answerFacts() {
        let waiting = waitingFacts
        waitingFacts = []
        for request in waiting { request.resume(returning: Bench.facts) }
    }

    /// Hands the cover to every request still waiting, as the player's
    /// CDN finally does.
    func answerArtwork() {
        let waiting = waitingArtwork
        waitingArtwork = []
        for request in waiting { request.resume(returning: artwork) }
    }

    /// Hands the archive's cover to every request still waiting.
    func answerRemoteCover() {
        let waiting = waitingRemoteCovers
        waitingRemoteCovers = []
        for request in waiting { request.resume(returning: remoteCover) }
    }

    /// Answers every read still waiting, as the player finally does.
    func answerRead() {
        let waiting = waitingReads
        waitingReads = []
        for read in waiting { read.resume(returning: track) }
    }

    /// Waits for the cycle under way to end. One that never does fails its
    /// test instead of hanging the suite: past the ceiling it is cancelled.
    func runs(seconds: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) async {
        guard let cycle = coordinator.cycle else { return }
        let ceiling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            XCTFail("the cycle never finished", file: file, line: line)
            cycle.cancel()
        }
        await cycle.value
        ceiling.cancel()
    }

    /// Records every phase the session goes through, and every state of
    /// its notes, in order.
    func watch(_ session: ListeningSession) -> SessionLog {
        let log = SessionLog()
        log.subscriptions = [
            session.$phase.sink { log.phases.append($0) },
            session.$notes.sink { log.notes.append($0) },
        ]
        return log
    }
}

private final class SessionLog {
    var phases: [ListeningSession.Phase] = []
    var notes: [String] = []
    var subscriptions: [AnyCancellable] = []
}

