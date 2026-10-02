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
        let bench = Bench(answer: .failure(NotesFailure()))
        bench.coordinator.trigger()
        let session = try XCTUnwrap(bench.coordinator.session)

        await bench.runs()
        XCTAssertEqual(session.phase, .error(NotesFailure().localizedDescription))
        XCTAssertEqual(session.track, .sample)
        XCTAssertEqual(bench.client.calls, 1)
        XCTAssertNotNil(bench.coordinator.session)
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

    // MARK: - Galette

    /// With Galette on the Mac, the card offers the artist, then the album.
    /// Galette is looked for once, as the panel opens.
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
                                        isPlaying: true,
                                        duration: 245.3)
}

/// One coordinator and the fakes it was built with.
@MainActor
private final class Bench {
    static let notes = "Takako Mamiya est une chanteuse japonaise de city pop. Love Trip est son seul album."
    /// The cover the fake player hands back, compared by identity.
    static let cover = NSImage(size: NSSize(width: 1, height: 1))

    let client: FakeNotesClient
    /// Galette, missing unless the test installs it.
    let galette: FakeGalette
    var coordinator: ListeningCoordinator { built }
    private var built: ListeningCoordinator!

    /// What the player says is playing, `nil` for nothing.
    let track: NowPlayingTrack?
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

    private var waitingReads: [CheckedContinuation<NowPlayingTrack?, Never>] = []
    private var waitingArtwork: [CheckedContinuation<NSImage?, Never>] = []
    private let artwork: NSImage?
    private let artworkWaits: Bool

    init(track: NowPlayingTrack? = .sample,
         answer: Result<String, Error> = .success(Bench.notes),
         hasClient: Bool = true,
         readsWait: Bool = false,
         galetteInstalled: Bool = false,
         artwork: NSImage? = nil,
         artworkWaits: Bool = false,
         model: ModelChoice = ListeningNotes.model) {
        self.track = track
        self.readsWait = readsWait
        self.artwork = artwork
        self.artworkWaits = artworkWaits
        let client = FakeNotesClient(answer)
        self.client = client
        galette = FakeGalette(installed: galetteInstalled)
        built = ListeningCoordinator(
            source: NowPlayingSource { [weak self] in
                guard let self else { return nil }
                reads += 1
                guard readsWait else { return track }
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
                guard artworkWaits else { return artwork }
                return await withCheckedContinuation { waitingArtwork.append($0) }
            },
            model: { model }
        )
    }

    /// Hands the cover to every request still waiting, as the player's
    /// CDN finally does.
    func answerArtwork() {
        let waiting = waitingArtwork
        waitingArtwork = []
        for request in waiting { request.resume(returning: artwork) }
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

    /// Lets the coordinator's task run: everything is on the main actor and
    /// nothing waits on the outside world, so a few turns are enough.
    func settle(until reached: () -> Bool) async {
        var turns = 0
        while !reached(), turns < 500 {
            await Task.yield()
            turns += 1
        }
    }

    /// Waits for something a timer decides — the panel closing itself. The
    /// ceiling keeps a panel that never closes from hanging the suite.
    func wait(seconds: TimeInterval = 2, until reached: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !reached(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
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

/// Answers a fixed text in two pieces, or throws, and keeps what each call
/// was sent.
///
/// `@unchecked Sendable`: every call is awaited before a test reads it.
private final class FakeNotesClient: TextStreamClient, @unchecked Sendable {
    private let answer: Result<String, Error>
    private(set) var calls = 0
    private(set) var texts: [String] = []
    private(set) var systems: [String] = []
    private(set) var budgets: [Int] = []

    init(_ answer: Result<String, Error>) { self.answer = answer }

    func streamCompletion(of text: String,
                          system: String,
                          maxTokens: Int,
                          onDelta: @escaping @Sendable (String) async -> Void) async throws -> StreamResult {
        calls += 1
        texts.append(text)
        systems.append(system)
        budgets.append(maxTokens)
        let notes = try answer.get()
        let middle = notes.index(notes.startIndex, offsetBy: notes.count / 2)
        await onDelta(String(notes[..<middle]))
        await onDelta(String(notes[middle...]))
        return StreamResult(text: notes, truncated: false, inputTokens: 0, outputTokens: 0)
    }
}

/// What a model that isn't answering looks like from here.
private struct NotesFailure: LocalizedError {
    var errorDescription: String? { "The API didn't answer" }
}
