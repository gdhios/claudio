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
        // Full catalog + "What's playing?" + the free row.
        XCTAssertEqual(PaletteCatalog.rows(matching: "").count, ClaudioAction.allCases.count + 2)

        // No action matches: only the free row remains, which reuses the
        // input as its instruction.
        let orphelines = PaletteCatalog.rows(matching: "Traduis en espagnol")
        XCTAssertEqual(orphelines.count, 1)
        XCTAssertEqual(orphelines[0].title, "Traduis en espagnol")
        XCTAssertEqual(orphelines[0].origin, .free(instruction: "Traduis en espagnol"))
        XCTAssertEqual(orphelines[0].request?.needsInstruction, false)
    }

    @MainActor
    func testTheFreeRowWithNoInstructionStaysPendingToSendLater() {
        let libre = PaletteCatalog.rows(matching: "").last { $0.origin != nil }
        XCTAssertEqual(libre?.origin, .free(instruction: ""))
        // With no instruction, the request can't be sent: the panel switches
        // to the input field instead of dispatching an empty instruction.
        XCTAssertEqual(libre?.request?.needsInstruction, true)
    }

    /// "What's playing?" transforms no selection: it comes after everything
    /// that does, the custom action included, so the ranks they had keep
    /// launching them. It shows whatever its own shortcut is bound to on the
    /// right, and sends no request — it opens a panel of its own.
    @MainActor
    func testWhatsPlayingComesAfterEverythingThatTransformsTheSelection() throws {
        let rows = PaletteCatalog.rows(matching: "")
        XCTAssertEqual(rows.map(\.kind),
                       ClaudioAction.allCases.map { .request(.catalog($0)) }
                           + [.request(.free(instruction: "")), .whatsPlaying])
        let row = try XCTUnwrap(rows.first { $0.kind == .whatsPlaying })
        XCTAssertEqual(row.title, "Qu'est-ce que j'écoute ?")
        XCTAssertEqual(row.detail, "Le morceau en cours, raconté par Claude")
        XCTAssertEqual(row.trailing, ListeningSession.shortcutDescription)
        XCTAssertNil(row.origin)
        XCTAssertNil(row.request)
    }

    /// Found the way the actions are: every word typed starts a word of its
    /// labels, or of the few a listener would reach for.
    @MainActor
    func testWhatsPlayingIsFoundByWhatOneListensTo() {
        for query in ["écoute", "ECOUTE", "morceau", "musique", "mus", "chanson", "qu'est-ce que"] {
            XCTAssertTrue(PaletteCatalog.rows(matching: query).contains { $0.kind == .whatsPlaying }, query)
        }
        XCTAssertFalse(PaletteCatalog.rows(matching: "trad").contains { $0.kind == .whatsPlaying })
    }

    @MainActor
    func testTheSelectionStaysWithinTheList() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "Bonjour"
        session.movePaletteSelection(by: -1)
        XCTAssertEqual(session.paletteSelection, 0)

        session.movePaletteSelection(by: 99)
        XCTAssertEqual(session.paletteSelection, session.paletteRows.count - 1)
        XCTAssertNotNil(session.selectedPaletteRow)
    }

    @MainActor
    func testFilteringResetsTheSelectionToTheTop() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "Bonjour"
        session.movePaletteSelection(by: 3)
        XCTAssertEqual(session.paletteSelection, 3)

        session.paletteQuery = "trad"
        XCTAssertEqual(session.paletteSelection, 0)
        XCTAssertEqual(session.selectedPaletteRow?.origin, .catalog(.translateFR))
    }
}
