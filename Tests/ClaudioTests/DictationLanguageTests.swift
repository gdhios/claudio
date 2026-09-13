import XCTest
@testable import Claudio

/// The closed list of dictation languages. Its `rawValue` is both the stored
/// setting and the BCP-47 identifier handed to the speech engine: it is
/// pinned here so a rename can't slip through.
final class DictationLanguageTests: XCTestCase {

    func testTheIdentifiersAreTheStoredValues() {
        XCTAssertEqual(DictationLanguage.allCases.map(\.rawValue),
                       ["fr-FR", "en-US", "en-GB", "es-ES", "de-DE", "it-IT", "pt-BR", "nl-NL"])
    }

    /// The setting reads back as itself, and an unknown value (written by a
    /// future version) yields nil so the caller falls back to its default.
    func testAStoredIdentifierReadsBack() {
        for language in DictationLanguage.allCases {
            XCTAssertEqual(DictationLanguage(rawValue: language.rawValue), language, language.rawValue)
        }
        XCTAssertNil(DictationLanguage(rawValue: "ja-JP"))
        XCTAssertNil(DictationLanguage(rawValue: ""))
    }

    /// The locale is what the engine is started with: language and region
    /// must both survive, since "en-US" and "en-GB" only differ by region.
    func testTheLocaleCarriesLanguageAndRegion() {
        XCTAssertEqual(DictationLanguage.frFR.locale.language.languageCode?.identifier, "fr")
        XCTAssertEqual(DictationLanguage.frFR.locale.region?.identifier, "FR")
        XCTAssertEqual(DictationLanguage.enGB.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(DictationLanguage.enGB.locale.region?.identifier, "GB")
        for language in DictationLanguage.allCases {
            XCTAssertEqual(language.locale.identifier(.bcp47), language.rawValue, language.rawValue)
        }
    }

    /// Two Englishes sit in the same picker: their labels have to tell them
    /// apart, in both interface languages.
    func testTheLabelsTellTheTwoEnglishesApart() {
        let previous = AppSettings.language
        defer { AppSettings.language = previous }

        AppSettings.language = .french
        XCTAssertEqual(DictationLanguage.frFR.displayName, "Français")
        XCTAssertEqual(DictationLanguage.enUS.displayName, "Anglais (États-Unis)")
        XCTAssertEqual(DictationLanguage.enGB.displayName, "Anglais (Royaume-Uni)")

        AppSettings.language = .english
        XCTAssertEqual(DictationLanguage.frFR.displayName, "French")
        XCTAssertEqual(DictationLanguage.enUS.displayName, "English (US)")
        XCTAssertEqual(DictationLanguage.enGB.displayName, "English (UK)")

        // No label is left empty or duplicated: the picker would be unreadable.
        for language in DictationLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty, language.rawValue)
        }
        XCTAssertEqual(Set(DictationLanguage.allCases.map(\.displayName)).count,
                       DictationLanguage.allCases.count)
    }
}
