import XCTest
@testable import Claudio

/// Verrouille le passage des jetons au montant affiché : c'est la seule chose
/// que l'utilisateur voit du compteur, et une dérive silencieuse y serait
/// invisible.
final class CostLedgerTests: XCTestCase {

    /// Tarifs publics Anthropic par million de jetons, entrée / sortie.
    func testLesTarifsSontCeuxPublies() {
        XCTAssertEqual(ClaudioModel.haiku45.inputPricePerMTok, 1)
        XCTAssertEqual(ClaudioModel.haiku45.outputPricePerMTok, 5)
        XCTAssertEqual(ClaudioModel.sonnet5.inputPricePerMTok, 2)
        XCTAssertEqual(ClaudioModel.sonnet5.outputPricePerMTok, 10)
        XCTAssertEqual(ClaudioModel.opus5.inputPricePerMTok, 5)
        XCTAssertEqual(ClaudioModel.opus5.outputPricePerMTok, 25)
    }

    /// Un million de jetons de chaque côté = la somme des deux tarifs.
    func testUnMillionDeJetonsCouteLaSommeDesDeuxTarifs() {
        for model in ClaudioModel.allCases {
            XCTAssertEqual(model.cost(inputTokens: 1_000_000, outputTokens: 1_000_000),
                           model.inputPricePerMTok + model.outputPricePerMTok,
                           accuracy: 1e-9, model.rawValue)
        }
    }

    func testCoutDUneActionCourte() {
        // 200 jetons d'entrée à 1 $/MTok + 200 de sortie à 5 $/MTok.
        XCTAssertEqual(ClaudioModel.haiku45.cost(inputTokens: 200, outputTokens: 200),
                       0.0012, accuracy: 1e-9)
        XCTAssertEqual(ClaudioModel.opus5.cost(inputTokens: 200, outputTokens: 200),
                       0.006, accuracy: 1e-9)
        withLanguage(.french) {
            XCTAssertEqual(ClaudioModel.haiku45.costHint, "≈ 0,12 $ pour 100 actions courtes")
            XCTAssertEqual(ClaudioModel.opus5.costHint, "≈ 0,60 $ pour 100 actions courtes")
        }
    }

    func testFormatMonetaire() {
        withLanguage(.french) {
            XCTAssertEqual(Money.format(0), "0,00 $")
            XCTAssertEqual(Money.format(0.0012), "< 0,01 $")
            XCTAssertEqual(Money.format(0.42), "0,42 $")
            XCTAssertEqual(Money.format(12.5), "12,50 $")
            XCTAssertEqual(Money.formatRounded(5), "5 $")
        }
    }

    /// En anglais le dollar passe devant et le séparateur est le point.
    func testFormatMonetaireAnglais() {
        withLanguage(.english) {
            XCTAssertEqual(Money.format(0), "$0.00")
            XCTAssertEqual(Money.format(0.0012), "< $0.01")
            XCTAssertEqual(Money.format(12.5), "$12.50")
            XCTAssertEqual(Money.formatRounded(5), "$5")
        }
    }

    /// Le temps d'une assertion, la langue est celle qu'on veut éprouver, et
    /// le réglage de la machine est rendu tel qu'il était.
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let previous = AppSettings.language
        AppSettings.language = language
        body()
        AppSettings.language = previous
    }

    // MARK: - Cumul du jour

    private let midi = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testLeCumulSAdditionneDansLaJournee() {
        let start = Calendar.current.startOfDay(for: midi)
        var jour = DailyCost(dayStart: start, total: 0, actions: 0)
        jour = jour.adding(0.10, at: midi)
        jour = jour.adding(0.32, at: midi.addingTimeInterval(3600))
        XCTAssertEqual(jour.total, 0.42, accuracy: 1e-9)
        XCTAssertEqual(jour.actions, 2)
        withLanguage(.french) { XCTAssertEqual(jour.formattedTotal, "0,42 $") }
    }

    func testLeCumulRepartDeZeroLeLendemain() {
        let start = Calendar.current.startOfDay(for: midi)
        let veille = DailyCost(dayStart: start, total: 5, actions: 12)
        let lendemain = midi.addingTimeInterval(24 * 3600)

        let apres = veille.adding(0.10, at: lendemain)
        XCTAssertEqual(apres.total, 0.10, accuracy: 1e-9)
        XCTAssertEqual(apres.actions, 1)
        XCTAssertEqual(apres.dayStart, Calendar.current.startOfDay(for: lendemain))

        // Même sans nouvelle action, l'affichage ne montre pas le total d'hier.
        let affiche = veille.current(at: lendemain)
        XCTAssertEqual(affiche.total, 0)
        XCTAssertEqual(affiche.actions, 0)
        XCTAssertEqual(veille.current(at: midi), veille, "la journée en cours est intacte")
    }

    /// Un stock hérité d'une version antérieure, ou vide, ne doit pas ressortir
    /// comme dépense du jour.
    @MainActor
    func testUnStockVideDemarreAZero() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.cost.\(UUID().uuidString)")!
        let ledger = CostLedger(defaults: defaults, now: midi)
        XCTAssertEqual(ledger.day.total, 0)
        XCTAssertEqual(ledger.day.actions, 0)
    }
}
