import XCTest
@testable import Claudio

/// With nothing selected, the palette still opens, and so does the custom
/// action: with no text to transform, what is typed or said goes out as a
/// request of its own, and Claude answers it. The palette offers what works
/// without a selection — "What's playing?", then the custom action. The
/// catalog shortcuts keep saying there's no selection, and closing by
/// themselves.
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
    /// Only the catalog stops there.
    func testWithNothingSelectedOnlyTheCatalogStops() {
        let palette = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        XCTAssertFalse(palette.hasSelection)
        XCTAssertEqual(palette.phaseAfterCapture, .choosingAction)
        // A palette waits for its row to be picked: it never closes by itself.
        XCTAssertNil(palette.phaseAfterCapture?.autoDismissDelay(.standard))

        // The custom action waits for its request, typed or said.
        XCTAssertEqual(CorrectionSession(request: .awaitingInstruction).phaseAfterCapture,
                       .askingInstruction)
        let spoken = CorrectionSession(request: .awaitingInstruction)
        spoken.phase = .listeningInstruction
        XCTAssertEqual(spoken.phaseAfterCapture, .listeningInstruction)
        // Relaunched from the history, it has it already: it goes out at once.
        XCTAssertNil(CorrectionSession(request: .free(instruction: "Traduis en espagnol")).phaseAfterCapture)

        for action in [ClaudioAction.correct, .summarize] {
            let session = CorrectionSession(action: action)
            XCTAssertEqual(session.phaseAfterCapture, .noSelection, action.rawValue)
            XCTAssertNotNil(session.phaseAfterCapture?.autoDismissDelay(.standard), action.rawValue)
        }
    }

    /// Over a selection nothing changes: the palette waits for a row, the
    /// custom action for its instruction, and everything else goes out.
    func testOverASelectionEverySessionCarriesOnAsBefore() {
        let palette = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        let typed = CorrectionSession(request: .awaitingInstruction)
        let relaunched = CorrectionSession(request: .free(instruction: "Traduis en espagnol"))
        let catalog = CorrectionSession(action: .correct)
        for session in [palette, typed, relaunched, catalog] { session.originalText = "Bonjour" }

        XCTAssertEqual(palette.phaseAfterCapture, .choosingAction)
        XCTAssertEqual(typed.phaseAfterCapture, .askingInstruction)
        XCTAssertNil(relaunched.phaseAfterCapture)
        XCTAssertNil(catalog.phaseAfterCapture)
    }

    /// Nothing selected, two rows: "What's playing?", then the custom action,
    /// ranked 1 and 2.
    func testWithoutASelectionWhatsPlayingThenTheCustomActionAreOffered() {
        let session = Self.paletteWithoutSelection()
        XCTAssertEqual(session.paletteRows.map(\.kind), [.whatsPlaying, .request(.free(instruction: ""))])
        XCTAssertEqual(session.selectedPaletteRow?.kind, .whatsPlaying)
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: false), 0)
        XCTAssertEqual(session.paletteIndex(forRank: 2, withCommand: false), 1)
        XCTAssertNil(session.paletteIndex(forRank: 3, withCommand: true))

        session.originalText = "Bonjour"
        XCTAssertTrue(session.hasSelection)
        XCTAssertEqual(session.paletteRows.count, ClaudioAction.allCases.count + 2)
    }

    /// Typing still filters, and the custom action is always there to take
    /// what was typed as its request: no query leaves the list empty.
    func testTypingFiltersAndWhatMatchesNothingBecomesTheRequest() {
        let session = Self.paletteWithoutSelection()
        session.paletteQuery = "musique"
        XCTAssertEqual(session.paletteRows.map(\.kind),
                       [.whatsPlaying, .request(.free(instruction: "musique"))])

        session.paletteQuery = "écris un mail pour décaler la réunion"
        XCTAssertEqual(session.paletteRows.map(\.kind),
                       [.request(.free(instruction: "écris un mail pour décaler la réunion"))])
        XCTAssertEqual(session.selectedPaletteRow?.request?.needsInstruction, false)
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: true), 0)
    }

    private static func paletteWithoutSelection() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.phase = .choosingAction
        return session
    }
}
