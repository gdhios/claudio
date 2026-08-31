import XCTest
@testable import Claudio

/// Le réglage de langue touche à une clé écrite dans UserDefaults, et à des
/// libellés qu'on ne relit plus une fois qu'ils sont traduits.
final class AppLanguageTests: XCTestCase {

    /// Les rawValue sont des clés de stockage : les renommer perdrait la
    /// langue de tous ceux qui en ont choisi une.
    func testLesIdentifiantsStockesNeChangentPas() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["system", "fr", "en"])
    }

    /// Un choix explicite prime sur la langue de la machine, dans les deux sens.
    func testUnChoixExpliciteContreditLeSysteme() {
        XCTAssertFalse(AppLanguage.french.showsEnglish)
        XCTAssertTrue(AppLanguage.english.showsEnglish)
    }

    /// Le filet : chaque libellé de la palette doit vraiment changer de langue.
    /// Un `loc` oublié laisserait du français dans une interface anglaise.
    func testToutLeCataloguePasseEnAnglais() {
        let previous = AppSettings.language
        defer { AppSettings.language = previous }

        AppSettings.language = .french
        let french = ClaudioAction.allCases.map { [$0.paletteTitle, $0.paletteDetail] }
        AppSettings.language = .english
        let english = ClaudioAction.allCases.map { [$0.paletteTitle, $0.paletteDetail] }

        for (action, (fr, en)) in zip(ClaudioAction.allCases, zip(french, english)) {
            // « Depuis n'importe quelle langue » est le seul sous-titre partagé
            // par deux actions : on compare bien paire à paire, pas en vrac.
            XCTAssertNotEqual(fr[0], en[0], "titre de \(action.rawValue)")
            XCTAssertNotEqual(fr[1], en[1], "sous-titre de \(action.rawValue)")
        }
    }
}
