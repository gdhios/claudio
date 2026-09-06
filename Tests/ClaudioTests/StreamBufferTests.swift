import XCTest
@testable import Claudio

/// The stream buffer is what keeps the window from advancing in jerks on
/// long responses. If it held onto one fragment too many, text would vanish
/// from the screen, and no one would catch it just by rereading the code.
@MainActor
final class StreamBufferTests: XCTestCase {

    private func session() -> CorrectionSession {
        CorrectionSession(action: .correct)
    }

    func testOpeningAStreamStartsFromABlankPage() {
        let session = session()
        session.correctedText = "d'avant"
        session.truncated = true
        session.justCopied = true

        session.beginStreaming()

        XCTAssertEqual(session.correctedText, "")
        XCTAssertFalse(session.truncated)
        XCTAssertFalse(session.justCopied)
        XCTAssertEqual(session.phase, .streaming)
    }

    /// The first fragment must not wait: it's the one that tells the user
    /// something is responding.
    func testTheFirstFragmentDisplaysImmediately() {
        let session = session()
        session.beginStreaming()

        session.appendStreamed("Bon")
        XCTAssertEqual(session.correctedText, "Bon")
    }

    /// The next ones wait for the flush, then arrive in order and all at once.
    func testTheNextFragmentsWaitForTheFlush() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bon")

        session.appendStreamed("jour")
        session.appendStreamed(" tout")
        session.appendStreamed(" le monde")
        XCTAssertEqual(session.correctedText, "Bon")

        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
    }

    func testFlushingAnEmptyBufferChangesNothing() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bonjour")

        session.flushStreamed()
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour")
    }

    /// The end of the stream is authoritative: it replaces the text
    /// published along the way, and whatever was still buffered goes with it.
    func testTheEndOfTheStreamReplacesEverythingAndLeavesNothingBehind() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bon")
        session.appendStreamed("jou")  // stays in the buffer

        session.finishStreaming(with: "Bonjour tout le monde", truncated: true)
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
        XCTAssertTrue(session.truncated)
        XCTAssertEqual(session.phase, .done)

        // The buffer was flushed, not just ignored: a late flush must not
        // come back and stick a piece onto the end of the final text.
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
    }

    /// ⏎ during the stream must not paste a half-written result.
    func testNothingIsPastedBeforeTheStreamEnds() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bonjour")
        XCTAssertFalse(session.canPaste)

        session.finishStreaming(with: "Bonjour", truncated: false)
        XCTAssertTrue(session.canPaste)

        // An empty result has nothing to paste, even when "done".
        session.finishStreaming(with: "", truncated: false)
        XCTAssertFalse(session.canPaste)
    }

    /// A stream that restarts ("Retry +") must not inherit the previous
    /// one's buffer.
    func testANewStreamDoesNotReattachAnythingFromThePrevious() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Premier")
        session.appendStreamed(" essai")

        session.beginStreaming()
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "")

        session.appendStreamed("Second")
        XCTAssertEqual(session.correctedText, "Second")
    }
}
