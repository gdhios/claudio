import XCTest
@testable import Claudio

/// What goes out to the keys, and how often. Two rules are at stake: a state
/// only travels when it has changed — a key redrawn on every keystroke of a
/// transcript would burn the Stream Deck's budget — and the microphone's
/// loudness is capped, because it moves dozens of times a second.
///
/// No socket and no clock: the frames are collected in an array and the time
/// is a variable the test moves by hand.
@MainActor
final class BridgeStatePublisherTests: XCTestCase {

    private var sent: [BridgeOutbound] = []
    private var clock = Date(timeIntervalSinceReferenceDate: 0)

    private lazy var publisher = BridgeStatePublisher(
        send: { [unowned self] in sent.append($0) },
        now: { [unowned self] in clock })

    /// Lets the publisher's recompute run. It is deferred by one turn on
    /// purpose: a `@Published` property tells its subscribers before it is
    /// written, so a state read on the spot would be the old one.
    private func settle() async {
        await Task.yield()
    }

    private func dictating(_ phase: DictationSession.Phase = .listening) -> DictationSession {
        let session = DictationSession(language: .frFR, model: .raw)
        session.phase = phase
        return session
    }

    private var states: [BridgeState] {
        sent.compactMap { if case .state(let state) = $0 { state } else { nil } }
    }

    private var levels: [Float] {
        sent.compactMap { if case .level(let value) = $0 { value } else { nil } }
    }

    // MARK: - The state

    /// A dictation starting is the first thing the keys learn about it.
    func testASessionStartingPublishesItsState() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()

        XCTAssertEqual(states, [BridgeState(correction: nil, dictation: session)])
        XCTAssertEqual(publisher.current, BridgeState(correction: nil, dictation: session))
    }

    /// A phase moving inside a session is what the keys are watching for:
    /// nothing else announces it.
    func testAPhaseChangePublishesOneState() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.phase = .cleaning
        await settle()

        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.phase, "cleaning")
    }

    /// The same phase set twice — a coordinator writing where it already
    /// was — says nothing: the frame would be identical.
    func testTheSamePhaseTwicePublishesOnce() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.phase = .cleaning
        await settle()
        session.phase = .cleaning
        await settle()

        XCTAssertEqual(states.count, 1)
    }

    /// A tap locking the dictation changes no phase: the key has to show it
    /// all the same, since the next press is what finishes it.
    func testLockingADictationPublishesAState() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.isLocked = true
        await settle()

        XCTAssertEqual(states.map(\.locked), [true])
    }

    /// The end of a dictation: Claudio goes back to waiting, and says so.
    func testASessionEndingPublishesTheIdleState() async {
        publisher.dictationSessionChanged(dictating())
        await settle()
        sent = []

        publisher.dictationSessionChanged(nil)
        await settle()

        XCTAssertEqual(states, [.idle])
        XCTAssertEqual(publisher.current, .idle)
    }

    /// Both at once: the dictation wins, and the correction ending under it
    /// changes nothing the keys can see.
    func testACorrectionEndingUnderADictationSaysNothing() async {
        let correction = CorrectionSession(request: ClaudioAction.correct.request)
        publisher.correctionSessionChanged(correction)
        publisher.dictationSessionChanged(dictating())
        await settle()
        sent = []

        publisher.correctionSessionChanged(nil)
        await settle()

        XCTAssertEqual(sent, [])
    }

    // MARK: - The microphone's loudness

    func testAListeningDictationPublishesItsNewestReading() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.levels = session.levels.adding(0.42)
        await settle()

        XCTAssertEqual(levels, [0.42])
    }

    /// Nothing is listening: a level would draw a waveform over a face that
    /// is cleaning up, or over nothing at all.
    func testALevelOutsideListeningPublishesNothing() async {
        let session = dictating(.cleaning)
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.levels = session.levels.adding(0.9)
        await settle()

        XCTAssertEqual(levels, [])
    }

    /// The cap, at its two edges: a second reading inside the interval is
    /// dropped — not queued, it is stale by the time it would go out — and
    /// the one after the interval goes.
    func testASecondReadingInsideTheIntervalIsDropped() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        session.levels = session.levels.adding(0.1)
        await settle()
        clock += 0.05
        session.levels = session.levels.adding(0.2)
        await settle()

        XCTAssertEqual(levels, [0.1])

        clock += 0.1  // 0.15 s since the first: past the interval
        session.levels = session.levels.adding(0.3)
        await settle()

        XCTAssertEqual(levels, [0.1, 0.3])
    }

    /// A real dictation: the engine reports thirty times a second, and the
    /// keys are drawn eight times at most. The dropped readings are gone,
    /// never sent late.
    func testThirtyReadingsInASecondAreCappedAtEight() async {
        let session = dictating()
        publisher.dictationSessionChanged(session)
        await settle()
        sent = []

        for step in 0..<30 {
            clock = Date(timeIntervalSinceReferenceDate: Double(step) / 30)
            session.levels = session.levels.adding(Float(step) / 30)
            await settle()
        }

        XCTAssertLessThanOrEqual(levels.count, 8, "\(levels)")
        XCTAssertGreaterThan(levels.count, 1, "a cap that drops everything is no cap")
    }

    /// A new dictation is not held to the previous one's budget: the first
    /// reading of a session always goes.
    func testANewSessionStartsItsOwnBudget() async {
        let first = dictating()
        publisher.dictationSessionChanged(first)
        await settle()
        first.levels = first.levels.adding(0.5)
        await settle()
        sent = []

        let second = dictating()
        publisher.dictationSessionChanged(second)
        await settle()
        second.levels = second.levels.adding(0.6)
        await settle()

        XCTAssertEqual(levels, [0.6])
    }

    // MARK: - Letting go

    /// The end of a session is announced like its start, and that is what
    /// lets go of it: a bridge still holding a finished dictation would be
    /// holding its transcript too.
    func testAFinishedSessionIsLetGoOf() async {
        weak var released: DictationSession?
        do {
            let session = dictating()
            released = session
            publisher.dictationSessionChanged(session)
            await settle()
            publisher.dictationSessionChanged(nil)
        }
        await settle()

        XCTAssertNil(released)
    }
}
