import Combine
import XCTest
@testable import Claudio

/// The dictation cycle, from the key going down to the text landing in the
/// app — with no microphone, no network, no pasteboard, no keystroke and no
/// window. The engine replays a fixed list of events, the model is a fake
/// client, the paste is a closure that only remembers what it was handed,
/// and the panel is never built.
@MainActor
final class DictationCoordinatorTests: XCTestCase {

    // MARK: - The whole cycle

    /// What a held press does: the partials show up while the key is down,
    /// the release closes the microphone, the model makes the transcript
    /// readable, and it's the cleaned-up text that gets pasted.
    func testAHeldPressPastesTheCleanedUpText() async throws {
        let bench = Bench()
        let coordinator = bench.coordinator

        coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(coordinator.session)
        let log = bench.watch(session)
        await bench.settle { session.transcript == "bonjour" }
        XCTAssertEqual(session.phase, .listening)
        XCTAssertEqual(bench.panels, 1)

        bench.hold(for: 1)
        coordinator.keyUp()
        XCTAssertEqual(bench.engine.stops, 1)
        await coordinator.cycle?.value

        XCTAssertEqual(log.phases, [.listening, .finishing, .cleaning, .pasting])
        XCTAssertEqual(session.cleanedText, "Bonjour.")
        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertNil(session.note)
        // Pasted: the panel has nothing left to say and closes itself.
        XCTAssertNil(coordinator.session)
    }

    /// The engine is started in the session's language, which is the
    /// shortcut's: that's the whole point of the second one.
    func testTheEngineListensInTheLanguageOfThePress() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .enUS)
        await bench.settle { bench.engine.starts == 1 }
        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["en-US"])
    }

    /// Raw and cleaned both enter the history, even though only the cleaned
    /// one was pasted: the transcript is the one thing a bad cleanup can't
    /// take away.
    func testTheHistoryKeepsTheRawNextToTheCleanedText() async {
        let bench = Bench()
        await bench.dictate()
        let entry = bench.history.recents.entries.first
        XCTAssertEqual(entry?.raw, "bonjour")
        XCTAssertEqual(entry?.cleaned, "Bonjour.")
        XCTAssertEqual(entry?.language, DictationLanguage.frFR.rawValue)
    }

    // MARK: - Presses that paste nothing

    /// Under 300 ms it isn't speech: a slip of the finger, or the shortcut
    /// pressed for something else. The microphone is cancelled rather than
    /// closed, and nothing is pasted or remembered.
    func testAPressTooShortIsIgnored() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }

        bench.hold(for: 0.2)
        bench.coordinator.keyUp()

        XCTAssertEqual(bench.engine.stops, 0)
        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
        XCTAssertNil(bench.coordinator.session)
    }

    /// Esc at any phase: the microphone is cancelled, the cycle is dropped,
    /// nothing is pasted. The clipboard is untouched because the only path
    /// that writes it is the paste, which never ran.
    func testEscapeCancelsWithoutPasting() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }

        bench.coordinator.escape()

        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
        XCTAssertNil(bench.coordinator.session)
    }

    /// A silence: the panel says it heard nothing rather than pasting an
    /// empty string, and no model is asked to clean up nothing.
    func testNothingHeardPastesNothing() async throws {
        let bench = Bench(events: [.partial("  "), .final("   ")])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        await bench.coordinator.cycle?.value

        XCTAssertEqual(session.phase, .empty)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.clientRequests.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
    }

    /// The engine gives up (no microphone, language not installed): its own
    /// message is shown, and the panel stays open on it.
    func testAnEngineFailureShowsItsMessage() async throws {
        let bench = Bench(events: [.failed(.microphoneDenied)])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.coordinator.cycle?.value

        XCTAssertEqual(session.phase,
                       .error(SpeechEngineError.microphoneDenied.localizedDescription))
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertNotNil(bench.coordinator.session)
    }

    // MARK: - Permissions

    /// Without the microphone and speech recognition, the press asks for
    /// them and explains itself — it doesn't listen. No panel opens, the
    /// engine is never started, and the next press is the one that dictates.
    func testARefusedMicrophoneListensToNothing() async {
        let bench = Bench(microphoneGranted: false)
        bench.coordinator.keyDown(language: .frFR)
        await bench.coordinator.permission?.value

        XCTAssertEqual(bench.permissionRequests, 1)
        XCTAssertEqual(bench.explanations, 1)
        XCTAssertEqual(bench.engine.starts, 0)
        XCTAssertEqual(bench.panels, 0)
        XCTAssertNil(bench.coordinator.session)
    }

    /// A permission already granted costs nothing: no prompt, no
    /// explanation, and the microphone opens on the press itself.
    func testAGrantedMicrophoneAsksForNothing() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }

        XCTAssertEqual(bench.permissionRequests, 0)
        XCTAssertEqual(bench.explanations, 0)
        XCTAssertNil(bench.coordinator.permission)
    }

    // MARK: - The cleanup, and what happens without it

    /// "Raw" names no model: the transcript is pasted as it was heard and
    /// nothing is ever asked of a client.
    func testRawPastesTheTranscriptWithoutAskingAModel() async {
        let bench = Bench(model: .raw)
        await bench.dictate()

        XCTAssertTrue(bench.clientRequests.isEmpty)
        XCTAssertEqual(bench.client.calls, 0)
        XCTAssertEqual(bench.pasted, ["bonjour"])
        // Nothing cleaned it up, so the history holds the transcript alone.
        XCTAssertNil(bench.history.recents.entries.first?.cleaned)
    }

    /// A dictation is never lost: the model failing costs the cleanup, not
    /// the text. The transcript is pasted and the panel says why.
    func testAFailedCleanupPastesTheTranscriptWithANote() async throws {
        let bench = Bench(answer: .failure(CleanupFailure()))
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertEqual(bench.pasted, ["bonjour"])
        XCTAssertEqual(session.note,
                       loc("Collé sans nettoyage : Ollama ne répond pas",
                           en: "Pasted without cleanup: Ollama isn’t answering"))
        XCTAssertNil(bench.history.recents.entries.first?.cleaned)
    }

    /// No client at all (a Claude model with no key in the Keychain): same
    /// outcome, the reason changes.
    func testAMissingKeyPastesTheTranscriptWithANote() async throws {
        let bench = Bench(hasClient: false)
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertEqual(bench.clientRequests, [.claude(.haiku45)])
        XCTAssertEqual(bench.pasted, ["bonjour"])
        XCTAssertEqual(session.note,
                       loc("Collé sans nettoyage : clé API manquante",
                           en: "Pasted without cleanup: no API key"))
    }

    // MARK: - The panel

    /// Nowhere to paste (Claudio itself was frontmost, or the app refused
    /// the keystroke): the panel stays open with the text, which Copy can
    /// still save. The history has it either way.
    func testAPasteWithNowhereToGoKeepsThePanelOpen() async throws {
        let bench = Bench()
        bench.pasteSucceeds = false
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertEqual(session.phase, .done)
        XCTAssertTrue(session.canCopy)
        XCTAssertNotNil(bench.coordinator.session)
        XCTAssertEqual(bench.history.recents.entries.count, 1)
    }

    /// A shortcut pressed while a dictation is running starts a fresh one:
    /// the first microphone is cancelled and its session dropped.
    func testANewPressRestartsTheCycle() async throws {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        let first = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        bench.coordinator.keyDown(language: .enUS)
        let second = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 2 }

        XCTAssertFalse(first === second)
        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["fr-FR", "en-US"])
        XCTAssertTrue(bench.pasted.isEmpty)
    }
}

// MARK: - The bench

/// One coordinator and the fakes it was built with, plus what a test needs
/// to drive it: a clock it moves by hand, and the texts the paste received.
@MainActor
private final class Bench {
    let engine: FakeSpeechEngine
    let client: FakeStreamClient
    let history: DictationHistory
    /// Built in `init` and never cleared: the tests see it as what it is.
    var coordinator: DictationCoordinator { built }
    private var built: DictationCoordinator!

    /// Every text the paste was handed, in order.
    var pasted: [String] = []
    /// Whether the paste finds an app to land in.
    var pasteSucceeds = true
    /// Every model a client was asked for: empty proves nothing was asked.
    var clientRequests: [ModelChoice] = []
    /// Whether the microphone and speech recognition are already granted.
    let microphoneGranted: Bool
    /// How many times the system prompts were asked for, and how many times
    /// the explanation replaced them.
    var permissionRequests = 0
    var explanations = 0
    /// How many panels were put on screen: nothing is heard without one.
    var panels = 0

    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init(events: [TranscriptEvent] = [.partial("bon"), .partial("bonjour"), .final("bonjour")],
         model: ModelChoice = .claude(.haiku45),
         answer: Result<String, Error> = .success("Bonjour."),
         hasClient: Bool = true,
         microphoneGranted: Bool = true) {
        self.microphoneGranted = microphoneGranted
        engine = FakeSpeechEngine(events)
        client = FakeStreamClient(answer)
        history = DictationHistory(
            defaults: UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!
        )
        let client = self.client
        built = DictationCoordinator(
            engine: engine,
            model: { model },
            client: { [weak self] choice in
                self?.clientRequests.append(choice)
                return hasClient ? client : nil
            },
            pasting: PasteService(
                isAllowed: { true },
                capture: { PasteTarget(app: nil, clipboard: nil) },
                paste: { [weak self] text, _ in
                    self?.pasted.append(text)
                    return self?.pasteSucceeds ?? false
                }
            ),
            microphone: MicrophoneGate(
                isGranted: { [weak self] in self?.microphoneGranted ?? false },
                request: { [weak self] in
                    self?.permissionRequests += 1
                    return self?.microphoneGranted ?? false
                },
                showExplanation: { [weak self] in self?.explanations += 1 }
            ),
            panel: { [weak self] _, _ in
                self?.panels += 1
                return nil
            },
            history: history,
            now: { [weak self] in self?.clock ?? .distantPast }
        )
    }

    /// Moves the clock forward: that's how long the key stayed down.
    func hold(for seconds: TimeInterval) { clock += seconds }

    /// A full dictation: press, speak, release, and wait for the text to land.
    func dictate(language: DictationLanguage = .frFR) async {
        coordinator.keyDown(language: language)
        await finish()
    }

    /// Releases a press already under way and waits for the cycle to end.
    func finish() async {
        await settle { engine.starts == 1 }
        hold(for: 1)
        coordinator.keyUp()
        await coordinator.cycle?.value
    }

    /// Lets the coordinator's task run. Everything here is on the main actor
    /// and nothing waits on the outside world, so a few turns are enough;
    /// the ceiling only keeps a broken cycle from hanging the suite.
    func settle(until reached: () -> Bool) async {
        var turns = 0
        while !reached(), turns < 500 {
            await Task.yield()
            turns += 1
        }
    }

    /// Records every phase the session goes through, in order.
    func watch(_ session: DictationSession) -> PhaseLog {
        let log = PhaseLog()
        log.subscription = session.$phase.sink { log.phases.append($0) }
        return log
    }
}

private final class PhaseLog {
    var phases: [DictationSession.Phase] = []
    var subscription: AnyCancellable?
}

/// Replays a fixed list of events. The partials go out as soon as the engine
/// starts, as a real one does while the key is held; the final waits for
/// `stop()`, since it's the microphone closing that ends a session. A
/// failure doesn't wait for anything.
///
/// `@unchecked Sendable`: everything it does happens on the main actor.
private final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let events: [TranscriptEvent]
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?

    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var startedLocales: [Locale] = []

    init(_ events: [TranscriptEvent]) { self.events = events }

    func start(locale: Locale) -> AsyncStream<TranscriptEvent> {
        starts += 1
        startedLocales.append(locale)
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        self.continuation = continuation
        for event in events {
            switch event {
            case .partial:
                continuation.yield(event)
            case .failed:
                continuation.yield(event)
                continuation.finish()
            case .final:
                break
            }
        }
        return stream
    }

    func stop() {
        stops += 1
        for case .final(let text) in events {
            continuation?.yield(.final(text))
        }
        continuation?.finish()
    }

    func cancel() {
        cancels += 1
        continuation?.finish()
    }
}

/// Answers a fixed text in two pieces, or throws. Counts its calls, so a
/// test can prove "Raw" never asks a model anything.
private final class FakeStreamClient: TextStreamClient, @unchecked Sendable {
    private let answer: Result<String, Error>
    private(set) var calls = 0
    private(set) var prompts: [String] = []

    init(_ answer: Result<String, Error>) { self.answer = answer }

    func streamCompletion(of text: String,
                          system: String,
                          maxTokens: Int,
                          onDelta: @escaping @Sendable (String) async -> Void) async throws -> StreamResult {
        calls += 1
        prompts.append(text)
        let cleaned = try answer.get()
        let middle = cleaned.index(cleaned.startIndex, offsetBy: cleaned.count / 2)
        await onDelta(String(cleaned[..<middle]))
        await onDelta(String(cleaned[middle...]))
        return StreamResult(text: cleaned, truncated: false, inputTokens: 0, outputTokens: 0)
    }
}

/// What a model that isn't answering looks like from here.
private struct CleanupFailure: LocalizedError {
    var errorDescription: String? {
        loc("Ollama ne répond pas", en: "Ollama isn’t answering")
    }
}
