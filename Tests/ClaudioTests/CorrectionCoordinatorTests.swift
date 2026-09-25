import XCTest
@testable import Claudio

/// A correction from the shortcut to the paste, with no permission, no
/// selection, no pasteboard, no network and no window. The capture finds a
/// fixed text or nothing, the model is a fake client, the paste only notes
/// what it was handed, and the panel is never built: the bench only counts
/// how many were asked for.
@MainActor
final class CorrectionCoordinatorTests: XCTestCase {

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
