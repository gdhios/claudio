import XCTest
@testable import Claudio

/// L'historique des consignes libres : la plus récente en tête, sans doublon,
/// plafonné. C'est le cœur type-valeur que les tests exercent — le magasin, lui,
/// ne fait que le persister.
final class TransformHistoryTests: XCTestCase {

    private let midi = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testLaPlusRecenteEstEnTete() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: midi)
        recents = recents.adding("Résume en trois points", at: midi.addingTimeInterval(60))
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Résume en trois points", "Traduis en espagnol"])
    }

    /// Relancer deux fois la même consigne ne la dédouble pas : elle remonte en
    /// tête, avec sa nouvelle date.
    func testUneConsigneRepeteeRemonteSansSeDedoubler() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: midi)
        recents = recents.adding("Passe au passé", at: midi.addingTimeInterval(60))
        recents = recents.adding("Traduis en espagnol", at: midi.addingTimeInterval(120))
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Traduis en espagnol", "Passe au passé"])
        XCTAssertEqual(recents.entries.first?.date, midi.addingTimeInterval(120))
    }

    /// Au-delà du plafond, la plus ancienne tombe.
    func testLePlafondFaitTomberLaPlusAncienne() {
        var recents = RecentTransforms()
        for i in 1...5 {
            recents = recents.adding("Consigne \(i)", at: midi.addingTimeInterval(Double(i)), limit: 3)
        }
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Consigne 5", "Consigne 4", "Consigne 3"])
    }

    /// Une consigne vide ou blanche n'entre pas dans l'historique, et un texte
    /// entouré d'espaces y entre nettoyé.
    func testUneConsigneVideEstIgnoreeEtLesBlancsSontRognes() {
        var recents = RecentTransforms()
        recents = recents.adding("   ", at: midi)
        XCTAssertTrue(recents.entries.isEmpty)
        recents = recents.adding("  Traduis en espagnol  ", at: midi)
        XCTAssertEqual(recents.entries.map(\.instruction), ["Traduis en espagnol"])
        // La même consigne, avec d'autres espaces, reste un doublon rogné.
        recents = recents.adding("Traduis en espagnol", at: midi.addingTimeInterval(60))
        XCTAssertEqual(recents.entries.count, 1)
    }

    func testVider() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: midi)
        recents = recents.cleared()
        XCTAssertTrue(recents.entries.isEmpty)
    }

    // MARK: - Magasin persistant

    @MainActor
    func testLeMagasinSurvitAuRedemarrage() {
        let suite = "ClaudioTests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let magasin = TransformHistory(defaults: defaults, limit: 20)
        magasin.record("Traduis en espagnol", at: midi)
        magasin.record("Résume en trois points", at: midi.addingTimeInterval(60))

        // Une nouvelle instance, comme au lancement suivant, relit le même stock.
        let relu = TransformHistory(defaults: defaults, limit: 20)
        XCTAssertEqual(relu.recents.entries.map(\.instruction),
                       ["Résume en trois points", "Traduis en espagnol"])
    }

    @MainActor
    func testLeMagasinVideEffaceLeStock() {
        let suite = "ClaudioTests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let magasin = TransformHistory(defaults: defaults, limit: 20)
        magasin.record("Traduis en espagnol", at: midi)
        magasin.clear()

        XCTAssertTrue(magasin.recents.entries.isEmpty)
        XCTAssertTrue(TransformHistory(defaults: defaults, limit: 20).recents.entries.isEmpty)
    }

    @MainActor
    func testUnStockVideDemarreVide() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.history.\(UUID().uuidString)")!
        XCTAssertTrue(TransformHistory(defaults: defaults, limit: 20).recents.entries.isEmpty)
    }
}
