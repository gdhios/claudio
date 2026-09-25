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
        // input as its instruction — over a selection or over nothing.
        for hasSelection in [true, false] {
            let orphelines = PaletteCatalog.rows(matching: "Traduis en espagnol", hasSelection: hasSelection)
            XCTAssertEqual(orphelines.count, 1)
            XCTAssertEqual(orphelines[0].title, "Traduis en espagnol")
            XCTAssertEqual(orphelines[0].origin, .free(instruction: "Traduis en espagnol"))
            XCTAssertEqual(orphelines[0].request?.needsInstruction, false)
        }

        // Nothing selected and nothing typed: there too, after "What's playing?".
        XCTAssertEqual(PaletteCatalog.rows(matching: "", hasSelection: false).last?.origin,
                       .free(instruction: ""))
    }

    @MainActor
    func testTheFreeRowWithNoInstructionStaysPendingToSendLater() {
        let libre = PaletteCatalog.rows(matching: "").last { $0.origin != nil }
        XCTAssertEqual(libre?.origin, .free(instruction: ""))
        // With no instruction, the request can't be sent: the panel switches
        // to the input field instead of dispatching an empty instruction.
        XCTAssertEqual(libre?.request?.needsInstruction, true)
    }

    /// Nothing typed, "What's playing?" — which transforms no selection —
    /// comes after everything that does, the custom action included, so the
    /// ranks they had keep launching them. Spaces are nothing typed. It
    /// shows whatever its own shortcut is bound to on the right, and sends
    /// no request: it opens a panel of its own.
    @MainActor
    func testWithNothingTypedWhatsPlayingComesAfterEverythingThatTransformsTheSelection() throws {
        let rows = PaletteCatalog.rows(matching: "")
        XCTAssertEqual(rows.map(\.kind),
                       ClaudioAction.allCases.map { .request(.catalog($0)) }
                           + [.request(.free(instruction: "")), .whatsPlaying])
        XCTAssertEqual(PaletteCatalog.rows(matching: "   ").map(\.kind), rows.map(\.kind))
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

    /// Typed, the query is a search: what it finds comes first and the
    /// escape hatch last, as for the catalog. "What's playing?" found this
    /// way takes the top, where Enter launches it; a query that finds an
    /// action and not it leaves it out.
    @MainActor
    func testATypedQueryPutsWhatsPlayingAmongTheMatchesBeforeTheCustomAction() {
        XCTAssertEqual(PaletteCatalog.rows(matching: "musique").map(\.kind),
                       [.whatsPlaying, .request(.free(instruction: "musique"))])
        XCTAssertEqual(PaletteCatalog.rows(matching: "trad").map(\.kind),
                       [.request(.catalog(.translateFR)), .request(.catalog(.translateEN)),
                        .request(.free(instruction: "trad"))])

        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "Bonjour"
        session.phase = .choosingAction
        session.paletteQuery = "musique"
        // Enter launches the selected row, which typing brings back to the top.
        XCTAssertEqual(session.paletteSelection, 0)
        XCTAssertEqual(session.selectedPaletteRow?.kind, .whatsPlaying)
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: true), 0)
    }

    /// The field hands its text back to the session when Return ends the
    /// editing, unchanged. That write must leave the row picked with ↓ where
    /// it is: taking the selection back to the top on it made ↓ then Enter
    /// launch the first row, whichever one was highlighted.
    @MainActor
    func testTheFieldWritingBackTheSameQueryKeepsTheSelection() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "Bonjour"
        session.phase = .choosingAction
        session.movePaletteSelection(by: 99)
        XCTAssertEqual(session.selectedPaletteRow?.kind, .whatsPlaying)

        session.paletteQuery = session.paletteQuery

        XCTAssertEqual(session.selectedPaletteRow?.kind, .whatsPlaying)
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
