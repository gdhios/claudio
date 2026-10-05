import XCTest
@testable import Claudio

/// Where a tab sits in the Settings sidebar, and the name a
/// `claudio://settings/…` link reaches it by.
final class SettingsSectionTests: XCTestCase {

    /// The Models tab sits right after the API key: the key, then what it
    /// pays for.
    func testTheModelsTabSitsAfterTheAPIKey() {
        let sections = SettingsSection.allCases
        let key = sections.firstIndex(of: .apiKey)!
        XCTAssertEqual(sections[key + 1], .models)
        XCTAssertEqual(SettingsSection.models.rawValue, "models")
    }

    /// The Music tab sits right after Dictation: the two things Claudio
    /// listens to, side by side.
    func testTheMusicTabSitsAfterDictation() {
        let sections = SettingsSection.allCases
        let dictation = sections.firstIndex(of: .dictation)!
        XCTAssertEqual(sections[dictation + 1], .music)
        XCTAssertEqual(SettingsSection.music.rawValue, "music")
    }

    /// The Ulanzi tab sits right after the Stream Deck: the two devices
    /// Claudio shows his face on, side by side. Its link name is its own.
    func testTheUlanziTabSitsAfterTheStreamDeck() {
        let sections = SettingsSection.allCases
        let streamDeck = sections.firstIndex(of: .streamDeck)!
        XCTAssertEqual(sections[streamDeck + 1], .ulanzi)
        XCTAssertEqual(SettingsSection.ulanzi.rawValue, "ulanzi")
        XCTAssertEqual(SettingsSection(linkName: "ulanzi"), .ulanzi)
    }

    /// The Tip tab sits between the devices and the prompts, and the menu,
    /// the website and anyone else reach it as `claudio://settings/tip`.
    func testTheTipTabSitsAfterUlanziAndOpensFromItsLink() {
        let sections = SettingsSection.allCases
        let ulanzi = sections.firstIndex(of: .ulanzi)!
        XCTAssertEqual(sections[ulanzi + 1], .tip)
        XCTAssertEqual(sections[ulanzi + 2], .prompts)
        XCTAssertEqual(SettingsSection.tip.rawValue, "tip")
        XCTAssertEqual(ClaudioURL.parse(URL(string: "claudio://settings/tip")!), .settings(.tip))
    }

    /// Named in the interface language, with its own badge.
    func testTheTipTabIsCalledTip() {
        useLanguage(.french)
        XCTAssertEqual(SettingsSection.tip.title, "Pourboire")
        XCTAssertEqual(SettingsSection.tip.symbolName, "cup.and.saucer.fill")
        useLanguage(.english)
        XCTAssertEqual(SettingsSection.tip.title, "Tip")
    }

    /// The one address the tab hands out: a typo would send a tip to
    /// somebody else, or nowhere.
    func testTheTipGoesToGuillaumesBuyMeACoffeePage() {
        XCTAssertEqual(Constants.tipURL.absoluteString, "https://buymeacoffee.com/gdhios")
    }
}
