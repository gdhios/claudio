import XCTest
@testable import Claudio

/// La mise à jour automatique tient sur deux décisions : « cette version
/// est-elle plus récente ? » et « ce version.json est-il lisible ? ». Une
/// erreur ici propose une mise à jour en boucle — ou ne la propose plus jamais.
final class UpdateCheckerTests: XCTestCase {

    func testPlusRecenteSeulementSiStrictementAuDessus() {
        XCTAssertTrue(UpdateChecker.isNewer("1.5.1", than: "1.5.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.5.1", than: "1.5.1"), "version égale : rien à proposer")
        XCTAssertFalse(UpdateChecker.isNewer("1.4.9", than: "1.5.0"), "flux en retard : pas de retour arrière")
    }

    /// L'ordre est numérique, pas alphabétique : le jour où sort une 1.10,
    /// elle doit dépasser la 1.9 (alphabétiquement, « 1.10 » < « 1.9 »).
    func testLaComparaisonEstNumerique() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.9", than: "1.10.0"))
    }

    /// Le format exact que la chaîne de release écrit sur le serveur : si l'un
    /// des deux bouge sans l'autre, plus personne n'est prévenu des mises à jour.
    @MainActor
    func testLeFluxEcritParLeScriptDeReleaseSeDecode() throws {
        let json = Data(#"{"version":"1.5.1","url":"https://claudio.okonoma.com/Claudio.zip"}"#.utf8)
        let feed = try JSONDecoder().decode(UpdateChecker.Feed.self, from: json)
        XCTAssertEqual(feed.version, "1.5.1")
        XCTAssertEqual(feed.url, URL(string: "https://claudio.okonoma.com/Claudio.zip"))
    }

    /// Un flux amputé ne doit pas passer pour valide : `checkNow` le convertit
    /// en `.failed`, jamais en « à jour ».
    @MainActor
    func testUnFluxIncompletEstRejete() {
        let sansURL = Data(#"{"version":"1.5.1"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateChecker.Feed.self, from: sansURL))
    }
}
