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
}
