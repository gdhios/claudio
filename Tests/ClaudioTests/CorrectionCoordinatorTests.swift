import XCTest
@testable import Claudio

/// A correction from the shortcut to the paste, with no permission, no
/// selection, no pasteboard, no network and no window. The capture finds a
/// fixed text or nothing, the model is a fake client, the paste only notes
/// what it was handed, and the panel is never built: the bench only counts
/// how many were asked for.
@MainActor
final class CorrectionCoordinatorTests: XCTestCase {

    /// The labels compared are French: the suite pins the language rather
    /// than inheriting it from the machine.
    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
        AppSettings.language = .french
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    /// Without Accessibility nothing can be read or pasted back: nothing is
    /// captured and no panel opens.
    func testWithoutAccessibilityNothingOpens() {
        let bench = Bench(selection: "Bonjour", allowed: false)
        XCTAssertNil(bench.coordinator.trigger(ClaudioAction.correct.request))
        XCTAssertNil(bench.coordinator.session)
        XCTAssertEqual(bench.captures, 0)
        XCTAssertEqual(bench.panels, 0)
    }

    /// The core gesture: the selection goes out under the action's prompt,
    /// the answer streams in, and Enter pastes it back, closing the panel.
    func testACatalogActionStreamsTheSelectionThenPastesItBack() async throws {
        let bench = Bench(selection: "Bonjour, je voulait savoir")
        bench.coordinator.trigger(action: .correct)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        let request = ClaudioAction.correct.request
        XCTAssertEqual(bench.client.texts, [request.userMessage(forText: "Bonjour, je voulait savoir")])
        XCTAssertEqual(bench.client.systems, [request.system])
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.correctedText, Bench.answer)
        XCTAssertEqual(bench.panels, 1)

        bench.coordinator.confirm()
        XCTAssertNil(bench.coordinator.session)
        await bench.settle { !bench.pasted.isEmpty }
        XCTAssertEqual(bench.pasted, [Bench.answer])
    }

    /// A catalog action has the selection for material: with nothing
    /// selected it says so, asks nothing of the model, and closes itself.
    func testACatalogShortcutOnNothingSelectedSaysSoThenClosesItself() async throws {
        let bench = Bench(selection: nil)
        bench.coordinator.trigger(action: .summarize)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        XCTAssertEqual(session.phase, .noSelection)
        XCTAssertEqual(bench.clientRequests, [])
        await bench.wait { bench.coordinator.session == nil }
        XCTAssertNil(bench.coordinator.session)
    }

    // MARK: - The custom action on nothing selected

    /// Tapped on nothing selected, the custom action no longer stops: its
    /// field asks for a request instead, and waits for it. What is typed
    /// goes out under the request's own prompt, from the same model as
    /// ever, and Claude's answer pastes at the cursor.
    func testTheCustomActionOnNothingSelectedAsksForARequestThenAnswersIt() async throws {
        let bench = Bench(selection: nil)
        bench.coordinator.triggerFreeAction()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(session.phase, .askingInstruction)
        XCTAssertFalse(session.hasSelection)
        // Waiting on someone, it doesn't take itself off the screen.
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(bench.coordinator.session === session)
        XCTAssertEqual(bench.clientRequests, [])

        session.instruction = "écris un mail pour décaler la réunion"
        bench.coordinator.confirm()
        await bench.runs()

        XCTAssertEqual(bench.clientRequests, [.claude(.haiku45)])
        XCTAssertEqual(bench.client.systems, [FreeRequest.system])
        XCTAssertEqual(bench.client.texts, ["<consigne>\nécris un mail pour décaler la réunion\n</consigne>"])
        XCTAssertEqual(session.request.origin, .free(instruction: "écris un mail pour décaler la réunion"))
        XCTAssertEqual(session.progressLabel, "Rédaction…")
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(bench.history.recents.entries.map(\.instruction),
                       ["écris un mail pour décaler la réunion"])

        bench.coordinator.confirm()
        await bench.settle { !bench.pasted.isEmpty }
        XCTAssertEqual(bench.pasted, [Bench.answer])
        XCTAssertEqual(bench.captures, 1)
    }

    /// Held on nothing selected: the panel goes on listening instead of
    /// saying there is no selection, and what was said goes out as the
    /// request.
    func testASpokenRequestOnNothingSelectedKeepsListeningThenGoesOut() async throws {
        let bench = Bench(selection: nil)
        let session = try XCTUnwrap(bench.coordinator.beginSpokenInstruction())
        await bench.runs()
        XCTAssertEqual(session.phase, .listeningInstruction)

        bench.coordinator.runSpokenInstruction("c'est quoi ce morceau ?")
        await bench.runs()
        XCTAssertEqual(bench.client.systems, [FreeRequest.system])
        XCTAssertEqual(bench.client.texts, ["<consigne>\nc'est quoi ce morceau ?\n</consigne>"])
        XCTAssertEqual(session.phase, .done)
    }

    /// Relaunched from the history on nothing selected: the instruction is
    /// known, so it goes out at once, as a request.
    func testARecentInstructionOnNothingSelectedGoesStraightOut() async throws {
        let bench = Bench(selection: nil)
        bench.coordinator.triggerRecent(instruction: "écris un mail pour décaler la réunion")
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        XCTAssertEqual(bench.client.systems, [FreeRequest.system])
        XCTAssertEqual(bench.client.texts, ["<consigne>\nécris un mail pour décaler la réunion\n</consigne>"])
        XCTAssertEqual(session.phase, .done)
    }

    /// The palette on nothing selected offers "What's playing?" and the
    /// custom action. What was typed, launched on the second, is the request.
    func testThePaletteOnNothingSelectedSendsWhatWasTypedAsTheRequest() async throws {
        let bench = Bench(selection: nil)
        bench.coordinator.triggerPalette()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(session.phase, .choosingAction)
        XCTAssertEqual(session.paletteRows.map(\.kind), [.whatsPlaying, .request(.free(instruction: ""))])

        session.paletteQuery = "écris un message pour partager ce que j'écoute"
        bench.coordinator.confirm()
        await bench.runs()
        XCTAssertEqual(bench.client.systems, [FreeRequest.system])
        XCTAssertEqual(bench.client.texts,
                       ["<consigne>\nécris un message pour partager ce que j'écoute\n</consigne>"])
    }

    /// "Try again" sends the same request again, and never captures a second
    /// time: the panel is up and key by then, and a simulated ⌘C would land
    /// in it — with nothing selected, there is nothing to read again anyway.
    func testTryingAgainOnNothingSelectedSendsTheSameRequestWithoutCapturing() async throws {
        let bench = Bench(selection: nil, track: .sample,
                          answers: [.failure(ModelFailure()), .success(Bench.answer)])
        bench.coordinator.triggerRecent(instruction: "c'est quoi ce morceau ?")
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(session.phase, .error(ModelFailure().localizedDescription))

        bench.coordinator.retry()
        await bench.runs()
        XCTAssertEqual(bench.captures, 1)
        XCTAssertEqual(bench.panels, 1)
        // The same question about the same track: the player isn't asked twice.
        XCTAssertEqual(bench.reads, 1)
        XCTAssertEqual(bench.client.systems, [FreeRequest.system, FreeRequest.system])
        XCTAssertEqual(bench.client.texts, Array(repeating: "<consigne>\nc'est quoi ce morceau ?\n</consigne>\n\n"
                                                     + Bench.trackBlock,
                                                 count: 2))
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.sentTrack, .sample)
    }

    // MARK: - The track playing

    /// Something plays: it goes out with the request, and the panel names
    /// the track that went — the line under the answer.
    func testTheTrackPlayingGoesOutWithTheRequestAndIsNamedUnderTheAnswer() async throws {
        let bench = Bench(selection: nil, track: .sample)
        bench.coordinator.triggerFreeAction()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertNil(session.sentTrack)

        session.instruction = "écris un message pour partager ce que j'écoute"
        bench.coordinator.confirm()
        await bench.runs()
        XCTAssertEqual(bench.client.texts, ["<consigne>\nécris un message pour partager ce que j'écoute\n</consigne>\n\n"
                                                + Bench.trackBlock])
        XCTAssertEqual(session.sentTrack, .sample)
        XCTAssertEqual(bench.reads, 1)
    }

    /// Over a selection too — "add the title I'm listening to at the end":
    /// the text as ever, the track after it, the transformation's prompt.
    func testOverASelectionTheTrackFollowsTheText() async throws {
        let bench = Bench(selection: "Bonne soirée !", track: .sample)
        bench.coordinator.triggerFreeAction()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        session.instruction = "ajoute le titre que j'écoute à la fin"
        bench.coordinator.confirm()
        await bench.runs()
        XCTAssertEqual(bench.client.systems, [ClaudioRequest.free(instruction: "ajoute le titre que j'écoute à la fin").system])
        XCTAssertEqual(bench.client.texts, [ClaudioRequest.wrappingSource("Bonne soirée !") + "\n\n" + Bench.trackBlock])
        XCTAssertEqual(session.sentTrack, .sample)
    }

    /// Nothing playing: the request goes alone, without a word about it, and
    /// no line names a track.
    func testNothingPlayingSendsTheRequestAloneAndNamesNoTrack() async throws {
        let bench = Bench(selection: nil, track: nil)
        bench.coordinator.triggerRecent(instruction: "écris un mail pour décaler la réunion")
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        XCTAssertEqual(bench.reads, 1)
        XCTAssertEqual(bench.client.texts, ["<consigne>\nécris un mail pour décaler la réunion\n</consigne>"])
        XCTAssertNil(session.sentTrack)
    }

    /// A catalog action never hears of the track: the player isn't even
    /// asked, nor Galette looked for, and the panel names nothing.
    func testACatalogActionNeverReadsTheTrack() async throws {
        let bench = Bench(selection: "Bonjour", track: .sample, galetteInstalled: true)
        bench.coordinator.trigger(action: .translateEN)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        XCTAssertEqual(bench.reads, 0)
        XCTAssertEqual(bench.galette.lookups, 0)
        XCTAssertEqual(bench.client.texts, [ClaudioAction.translateEN.request.userMessage(forText: "Bonjour")])
        XCTAssertNil(session.sentTrack)
        XCTAssertEqual(session.galetteLinks, [])
    }

    /// With Galette on the Mac, the line naming the track sent offers it in
    /// Galette — once it went out, not before. A button leaves the panel up:
    /// an answer not pasted yet must not go with it.
    func testWithGaletteTheTrackSentOffersItsButtonsAndAClickKeepsThePanel() async throws {
        let bench = Bench(selection: nil, track: .sample, galetteInstalled: true)
        bench.coordinator.triggerFreeAction()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(bench.galette.lookups, 1)
        XCTAssertEqual(session.galetteLinks, [])

        session.instruction = "écris un message pour partager ce que j'écoute"
        bench.coordinator.confirm()
        await bench.runs()
        XCTAssertEqual(session.galetteLinks, [.artist(name: "間宮貴子"),
                                              .album(artist: "間宮貴子", title: "LOVE TRIP")])

        let artist = GaletteLink.artist(name: "間宮貴子")
        bench.coordinator.openInGalette(artist)
        XCTAssertEqual(bench.galette.opened, [artist.url])
        XCTAssertTrue(bench.coordinator.session === session)
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(bench.pasted, [])
    }

    /// Without Galette the line names the track and offers nothing more.
    func testWithoutGaletteTheTrackSentOffersNothing() async throws {
        let bench = Bench(selection: nil, track: .sample)
        bench.coordinator.triggerRecent(instruction: "c'est quoi ce morceau ?")
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()

        XCTAssertEqual(session.sentTrack, .sample)
        XCTAssertNil(session.galette)
        XCTAssertEqual(session.galetteLinks, [])
    }

    /// The palette asks the player as it opens, since it may become the
    /// custom action; a catalog row picked in it sends no track all the same.
    func testACatalogRowPickedInThePaletteSendsNoTrack() async throws {
        let bench = Bench(selection: "Bonjour", track: .sample)
        bench.coordinator.triggerPalette()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(bench.reads, 1)

        session.paletteQuery = "anglais"
        bench.coordinator.confirm()
        await bench.runs()
        XCTAssertEqual(bench.client.texts, [ClaudioAction.translateEN.request.userMessage(forText: "Bonjour")])
        XCTAssertNil(session.sentTrack)
    }

    /// The player is read while the selection is captured, and never holds
    /// the panel up: it opens, asks for the request, and only the sending
    /// waits for the answer — long in by then, when the request is typed.
    func testThePlayerIsReadAlongsideTheCaptureAndOnlyWaitedForToSend() async throws {
        let bench = Bench(selection: nil, track: .sample, readsWait: true)
        bench.coordinator.triggerFreeAction()
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(bench.reads, 1)
        XCTAssertEqual(bench.panels, 1)
        XCTAssertEqual(session.phase, .askingInstruction)

        session.instruction = "c'est quoi ce morceau ?"
        bench.coordinator.confirm()
        await bench.settle { false }
        XCTAssertEqual(bench.client.calls, 0)

        bench.answerRead()
        await bench.runs()
        XCTAssertEqual(bench.client.texts, ["<consigne>\nc'est quoi ce morceau ?\n</consigne>\n\n" + Bench.trackBlock])
        XCTAssertEqual(session.sentTrack, .sample)
    }

    /// Esc while the player is still answering: the answer that comes
    /// afterwards sends nothing.
    func testEscapeWhileThePlayerAnswersSendsNothing() async throws {
        let bench = Bench(selection: nil, track: .sample, readsWait: true)
        bench.coordinator.triggerRecent(instruction: "c'est quoi ce morceau ?")
        let task = try XCTUnwrap(bench.coordinator.streamTask)
        // The model's client is made: all that's left before sending is the track.
        await bench.settle { bench.clientRequests.count == 1 }
        XCTAssertEqual(bench.reads, 1)

        bench.coordinator.dismiss()
        bench.answerRead()
        await task.value
        XCTAssertEqual(bench.client.calls, 0)
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
                                        isPlaying: false,
                                        duration: 245.3)
}

/// One coordinator and the fakes it was built with.
@MainActor
private final class Bench: AsyncWaiting {
    static let answer = "Bonjour, je voulais savoir."
    /// `NowPlayingTrack.sample`, the way the model reads it.
    static let trackBlock = """
        <morceau_en_cours>
        titre : 真夜中のジョーク
        artiste : 間宮貴子
        album : LOVE TRIP
        lecteur : Spotify
        </morceau_en_cours>
        """

    let client: FakeTextStreamClient
    /// Galette, missing unless the test installs it.
    let galette: FakeGalette
    var coordinator: CorrectionCoordinator { built }
    private var built: CorrectionCoordinator!

    /// What the capture finds: `nil` is nothing selected.
    let selection: String?
    /// What the player says is playing, `nil` for nothing.
    let track: NowPlayingTrack?
    /// Reads wait for `answerRead()` instead of answering at once: that's
    /// the player still being read when the request is sent, or Esc comes.
    let readsWait: Bool
    /// How many times the player was read: zero proves it never was.
    private(set) var reads = 0
    private var waitingReads: [CheckedContinuation<NowPlayingTrack?, Never>] = []
    /// How many times the selection was captured.
    private(set) var captures = 0
    /// How many panels were put on screen.
    private(set) var panels = 0
    /// Every model a client was asked for: empty proves nothing was asked.
    private(set) var clientRequests: [ModelChoice] = []
    /// Every text handed to the paste, in order.
    private(set) var pasted: [String] = []
    /// The custom instructions remembered, in a store nobody else reads.
    let history: TransformHistory

    init(selection: String?,
         track: NowPlayingTrack? = nil,
         readsWait: Bool = false,
         allowed: Bool = true,
         hasClient: Bool = true,
         answers: [Result<String, Error>] = [.success(Bench.answer)],
         galetteInstalled: Bool = false) {
        self.selection = selection
        self.track = track
        self.readsWait = readsWait
        let client = FakeTextStreamClient(answers)
        self.client = client
        galette = FakeGalette(installed: galetteInstalled)
        history = TransformHistory(defaults: InMemoryDefaults())
        built = CorrectionCoordinator(
            durations: .init(empty: .milliseconds(20), failure: .milliseconds(20)),
            pasting: PasteService(
                isAllowed: { allowed },
                capture: { PasteTarget() },
                paste: { [weak self] text, _ in
                    self?.pasted.append(text)
                }
            ),
            selection: { [weak self] in
                self?.captures += 1
                return selection
            },
            source: NowPlayingSource { [weak self] in
                guard let self else { return nil }
                reads += 1
                guard readsWait else { return track }
                return await withCheckedContinuation { waitingReads.append($0) }
            },
            client: { [weak self] choice in
                self?.clientRequests.append(choice)
                return hasClient ? client : nil
            },
            panel: { [weak self] _, _ in
                self?.panels += 1
                return nil
            },
            galette: galette.service,
            history: history
        )
    }

    /// Answers every read still waiting, as the player finally does.
    func answerRead() {
        let waiting = waitingReads
        waitingReads = []
        for read in waiting { read.resume(returning: track) }
    }

    /// Waits for the capture and the stream under way to end. One that never
    /// does fails its test instead of hanging the suite.
    func runs(seconds: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) async {
        guard let task = coordinator.streamTask else { return }
        let ceiling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            XCTFail("the correction never finished", file: file, line: line)
            task.cancel()
        }
        await task.value
        ceiling.cancel()
    }

}

