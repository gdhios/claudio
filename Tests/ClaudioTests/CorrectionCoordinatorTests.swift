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
        let bench = Bench(selection: nil, answers: [.failure(AnswerFailure()), .success(Bench.answer)])
        bench.coordinator.triggerRecent(instruction: "c'est quoi ce morceau ?")
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.runs()
        XCTAssertEqual(session.phase, .error(AnswerFailure().localizedDescription))

        bench.coordinator.retry()
        await bench.runs()
        XCTAssertEqual(bench.captures, 1)
        XCTAssertEqual(bench.panels, 1)
        XCTAssertEqual(bench.client.systems, [FreeRequest.system, FreeRequest.system])
        XCTAssertEqual(bench.client.texts, Array(repeating: "<consigne>\nc'est quoi ce morceau ?\n</consigne>",
                                                 count: 2))
        XCTAssertEqual(session.phase, .done)
    }
}

// MARK: - The bench

/// One coordinator and the fakes it was built with.
@MainActor
private final class Bench {
    static let answer = "Bonjour, je voulais savoir."

    let client: FakeAnswerClient
    var coordinator: CorrectionCoordinator { built }
    private var built: CorrectionCoordinator!

    /// What the capture finds: `nil` is nothing selected.
    let selection: String?
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
         allowed: Bool = true,
         hasClient: Bool = true,
         answers: [Result<String, Error>] = [.success(Bench.answer)]) {
        self.selection = selection
        let client = FakeAnswerClient(answers)
        self.client = client
        history = TransformHistory(defaults: UserDefaults(suiteName: "ClaudioTests.correction.\(UUID().uuidString)")!)
        built = CorrectionCoordinator(
            durations: .init(empty: .milliseconds(20), failure: .milliseconds(20)),
            pasting: PasteService(
                isAllowed: { allowed },
                capture: { PasteTarget() },
                paste: { [weak self] text, _ in
                    self?.pasted.append(text)
                    return true
                }
            ),
            selection: { [weak self] in
                self?.captures += 1
                return selection
            },
            client: { [weak self] choice in
                self?.clientRequests.append(choice)
                return hasClient ? client : nil
            },
            panel: { [weak self] _, _ in
                self?.panels += 1
                return nil
            },
            history: history
        )
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

    /// Lets the coordinator's tasks run: everything is on the main actor and
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
}

/// Answers in two pieces, one answer per call — the last one again once the
/// list runs out — and keeps what each call was sent.
///
/// `@unchecked Sendable`: every call is awaited before a test reads it.
private final class FakeAnswerClient: TextStreamClient, @unchecked Sendable {
    private var answers: [Result<String, Error>]
    private(set) var texts: [String] = []
    private(set) var systems: [String] = []

    init(_ answers: [Result<String, Error>]) { self.answers = answers }

    var calls: Int { texts.count }

    func streamCompletion(of text: String,
                          system: String,
                          maxTokens: Int,
                          onDelta: @escaping @Sendable (String) async -> Void) async throws -> StreamResult {
        texts.append(text)
        systems.append(system)
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        let full = try answer.get()
        let middle = full.index(full.startIndex, offsetBy: full.count / 2)
        await onDelta(String(full[..<middle]))
        await onDelta(String(full[middle...]))
        return StreamResult(text: full, truncated: false, inputTokens: 0, outputTokens: 0)
    }
}

/// What a model that isn't answering looks like from here.
private struct AnswerFailure: LocalizedError {
    var errorDescription: String? { "The API didn't answer" }
}
