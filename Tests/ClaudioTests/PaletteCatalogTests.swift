import XCTest
@testable import Claudio

/// La palette est le seul endroit où l'utilisateur cherche une action au
/// clavier : si le filtre rate une action ou si la ligne libre disparaît, il
/// n'a plus aucun moyen d'arriver à ce qu'il veut.
final class PaletteCatalogTests: XCTestCase {

    /// Les libellés attendus sont français : la suite fixe la langue plutôt
    /// que d'hériter de celle de la machine, sinon elle échoue sur un runner
    /// anglais (la CI) et passe sur un Mac français.
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

    func testSaisieVideRendToutLeCatalogue() {
        XCTAssertEqual(PaletteCatalog.matches("").count, ClaudioAction.allCases.count)
        XCTAssertEqual(PaletteCatalog.matches("   ").count, ClaudioAction.allCases.count)
    }

    func testTousLesMotsDoiventCorrespondre() {
        // « trad ang » : les deux mots se retrouvent dans la traduction en
        // anglais, mais pas dans celle en français.
        let deuxMots = PaletteCatalog.matches("trad ang")
        XCTAssertEqual(deuxMots, [.translateEN])
        // Un seul des deux mots suffit à ramener les deux traductions.
        XCTAssertEqual(Set(PaletteCatalog.matches("trad")), Set([.translateFR, .translateEN]))
    }

    func testAccentsEtCasseIgnores() {
        XCTAssertEqual(PaletteCatalog.matches("FRANCAIS"), [.translateFR])
        XCTAssertEqual(PaletteCatalog.matches("français"), [.translateFR])
    }

    func testSaisieSansCorrespondanceNeLaissePasSansIssue() {
        XCTAssertTrue(PaletteCatalog.matches("zzz").isEmpty)
    }

    @MainActor
    func testLaLigneLibreEstToujoursPresente() {
        // Catalogue complet + la ligne libre.
        XCTAssertEqual(PaletteCatalog.rows(matching: "").count, ClaudioAction.allCases.count + 1)

        // Aucune action ne correspond : il reste la ligne libre, qui reprend la
        // saisie comme consigne.
        let orphelines = PaletteCatalog.rows(matching: "Traduis en espagnol")
        XCTAssertEqual(orphelines.count, 1)
        XCTAssertEqual(orphelines[0].title, "Traduis en espagnol")
        XCTAssertEqual(orphelines[0].origin, .free(instruction: "Traduis en espagnol"))
        XCTAssertFalse(orphelines[0].request.needsInstruction)
    }

    @MainActor
    func testLigneLibreSansConsigneResteAEnvoyerPlusTard() {
        let libre = PaletteCatalog.rows(matching: "").last
        XCTAssertEqual(libre?.origin, .free(instruction: ""))
        // Sans consigne, la requête n'est pas envoyable : le panneau bascule
        // sur le champ de saisie plutôt que d'expédier une instruction vide.
        XCTAssertEqual(libre?.request.needsInstruction, true)
    }

    @MainActor
    func testLaSelectionResteDansLaListe() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.movePaletteSelection(by: -1)
        XCTAssertEqual(session.paletteSelection, 0)

        session.movePaletteSelection(by: 99)
        XCTAssertEqual(session.paletteSelection, session.paletteRows.count - 1)
        XCTAssertNotNil(session.selectedPaletteRow)
    }

    @MainActor
    func testFiltrerRemetLaSelectionEnTete() {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.movePaletteSelection(by: 3)
        XCTAssertEqual(session.paletteSelection, 3)

        session.paletteQuery = "trad"
        XCTAssertEqual(session.paletteSelection, 0)
        XCTAssertEqual(session.selectedPaletteRow?.origin, .catalog(.translateFR))
    }
}
