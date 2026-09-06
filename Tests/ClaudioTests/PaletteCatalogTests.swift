import XCTest
@testable import Claudio

/// The palette is the only place a user searches for an action by keyboard:
/// if the filter misses an action or the free row disappears, they have no
/// way left to reach what they want.
final class PaletteCatalogTests: XCTestCase {

    /// The expected labels are French: the suite pins the language rather than
    /// inheriting it from the machine, otherwise it fails on an English runner
    /// (CI) and passes on a French Mac.
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

    func testEmptyInputReturnsTheWholeCatalog() {
        XCTAssertEqual(PaletteCatalog.matches("").count, ClaudioAction.allCases.count)
        XCTAssertEqual(PaletteCatalog.matches("   ").count, ClaudioAction.allCases.count)
    }

    func testEveryWordMustMatch() {
        // "trad ang": both words are found in the English translation action,
        // but not in the French one.
        let deuxMots = PaletteCatalog.matches("trad ang")
        XCTAssertEqual(deuxMots, [.translateEN])
        // Either word alone is enough to bring back both translations.
        XCTAssertEqual(Set(PaletteCatalog.matches("trad")), Set([.translateFR, .translateEN]))
    }

    func testAccentsAndCaseAreIgnored() {
        XCTAssertEqual(PaletteCatalog.matches("FRANCAIS"), [.translateFR])
        XCTAssertEqual(PaletteCatalog.matches("français"), [.translateFR])
    }

    func testInputWithNoMatchDoesNotLeaveADeadEnd() {
        XCTAssertTrue(PaletteCatalog.matches("zzz").isEmpty)
    }

    @MainActor
    func testTheFreeRowIsAlwaysPresent() {
        // Full catalog + the free row.
        XCTAssertEqual(PaletteCatalog.rows(matching: "").count, ClaudioAction.allCases.count + 1)

        // No action matches: only the free row remains, which reuses the
        // input as its instruction.
        let orphelines = PaletteCatalog.rows(matching: "Traduis en espagnol")
        XCTAssertEqual(orphelines.count, 1)
        XCTAssertEqual(orphelines[0].title, "Traduis en espagnol")
        XCTAssertEqual(orphelines[0].origin, .free(instruction: "Traduis en espagnol"))
        XCTAssertFalse(orphelines[0].request.needsInstruction)
    }

    @MainActor
    func testTheFreeRowWithNoInstructionStaysPendingToSendLater() {
        let libre = PaletteCatalog.rows(matching: "").last
        XCTAssertEqual(libre?.origin, .free(instruction: ""))
        // With no instruction, the request can't be sent: the panel switches
        // to the input field instead of dispatching an empty instruction.
        XCTAssertEqual(libre?.request.needsInstruction, true)
    }

    @MainActor
    func testTheSelectionStaysWithinTheList() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.movePaletteSelection(by: -1)
        XCTAssertEqual(session.paletteSelection, 0)

        session.movePaletteSelection(by: 99)
        XCTAssertEqual(session.paletteSelection, session.paletteRows.count - 1)
        XCTAssertNotNil(session.selectedPaletteRow)
    }

    @MainActor
    func testFilteringResetsTheSelectionToTheTop() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.movePaletteSelection(by: 3)
        XCTAssertEqual(session.paletteSelection, 3)

        session.paletteQuery = "trad"
        XCTAssertEqual(session.paletteSelection, 0)
        XCTAssertEqual(session.selectedPaletteRow?.origin, .catalog(.translateFR))
    }
}
