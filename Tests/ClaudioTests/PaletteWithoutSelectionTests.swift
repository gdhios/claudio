import XCTest
@testable import Claudio

/// With nothing selected, the palette still opens: it's a question, not an
/// order, and some of what it offers needs no selection at all — "What's
/// playing?", today. It shows that and nothing else: the actions, the
/// custom one included, would have nothing to work on. The action shortcuts
/// keep saying there's no selection, and closing by themselves.
@MainActor
final class PaletteWithoutSelectionTests: XCTestCase {

    /// The labels searched are French: the suite pins the language rather
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

    /// The capture came back empty: this is where each kind of session goes.
    func testOnlyThePaletteOpensWithoutASelection() {
        let palette = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        XCTAssertFalse(palette.hasSelection)
        XCTAssertEqual(palette.phaseWithoutSelection, .choosingAction)
        // A palette waits for its row to be picked: it never closes by itself.
        XCTAssertNil(palette.phaseWithoutSelection.autoDismissDelay(.standard))

        for session in [CorrectionSession(action: .correct),
                        CorrectionSession(action: .summarize),
                        CorrectionSession(request: .awaitingInstruction)] {
            XCTAssertEqual(session.phaseWithoutSelection, .noSelection)
            XCTAssertNotNil(session.phaseWithoutSelection.autoDismissDelay(.standard))
        }
    }

    /// Nothing selected, one row: the one that needs nothing selected. The
    /// free row isn't there — it would have nothing to transform — and the
    /// ranks start over from it.
    func testWithoutASelectionOnlyWhatWorksWithoutOneIsOffered() {
        let session = Self.paletteWithoutSelection()
        XCTAssertEqual(session.paletteRows.map(\.kind), [.whatsPlaying])
        XCTAssertEqual(session.selectedPaletteRow?.kind, .whatsPlaying)
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: false), 0)
        XCTAssertNil(session.paletteIndex(forRank: 2, withCommand: true))

        session.originalText = "Bonjour"
        XCTAssertTrue(session.hasSelection)
        XCTAssertEqual(session.paletteRows.count, ClaudioAction.allCases.count + 2)
    }

    /// Typing still filters. A query that matches nothing leaves an empty
    /// list — no free row to fall back on — and nothing for Enter or a digit
    /// to launch.
    func testTypingStillFiltersAndAnEmptyListLaunchesNothing() {
        let session = Self.paletteWithoutSelection()
        session.paletteQuery = "musique"
        XCTAssertEqual(session.paletteRows.map(\.kind), [.whatsPlaying])

        session.paletteQuery = "traduis en espagnol"
        XCTAssertTrue(session.paletteRows.isEmpty)
        XCTAssertNil(session.selectedPaletteRow)
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: true))
        session.movePaletteSelection(by: 1)
        XCTAssertEqual(session.paletteSelection, 0)
    }

    private static func paletteWithoutSelection() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.phase = session.phaseWithoutSelection
        return session
    }
}
