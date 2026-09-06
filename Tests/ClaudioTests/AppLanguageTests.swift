import XCTest
@testable import Claudio

/// The language setting touches a key written to UserDefaults, and labels
/// that are never re-read once translated.
final class AppLanguageTests: XCTestCase {

    /// The rawValues are storage keys: renaming them would lose the language
    /// of everyone who chose one.
    func testTheStoredIdentifiersDontChange() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["system", "fr", "en"])
    }

    /// An explicit choice overrides the machine's language, in both directions.
    func testAnExplicitChoiceOverridesTheSystem() {
        XCTAssertFalse(AppLanguage.french.showsEnglish)
        XCTAssertTrue(AppLanguage.english.showsEnglish)
    }

    /// The safety net: every palette label must actually change language.
    /// A forgotten `loc` would leave French in an English interface.
    func testTheWholeCatalogSwitchesToEnglish() {
        let previous = AppSettings.language
        defer { AppSettings.language = previous }

        AppSettings.language = .french
        let french = ClaudioAction.allCases.map { [$0.paletteTitle, $0.paletteDetail] }
        AppSettings.language = .english
        let english = ClaudioAction.allCases.map { [$0.paletteTitle, $0.paletteDetail] }

        for (action, (fr, en)) in zip(ClaudioAction.allCases, zip(french, english)) {
            // "From any language" is the only subtitle shared by two actions:
            // compare pair by pair, not in bulk.
            XCTAssertNotEqual(fr[0], en[0], "title of \(action.rawValue)")
            XCTAssertNotEqual(fr[1], en[1], "subtitle of \(action.rawValue)")
        }
    }
}
