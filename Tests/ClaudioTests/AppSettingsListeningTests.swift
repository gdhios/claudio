import XCTest
@testable import Claudio

/// What the Music tab sets: how long the notes are, whether MusicBrainz
/// completes them, whether the cover shows. All on by default — the
/// decision of 2026-10-02 — and each under its own key.
final class AppSettingsListeningTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    func testTheDefaultsAreOnAndThreeSentences() {
        let preferences = ListeningPreferences.current(in: defaults)
        XCTAssertTrue(preferences.musicBrainz)
        XCTAssertTrue(preferences.showsArtwork)
        XCTAssertEqual(preferences.detail, .threeSentences)
    }

    func testEachSettingReadsBackUnderItsOwnKey() {
        AppSettings.setMusicBrainzEnabled(false, in: defaults)
        AppSettings.setShowsArtwork(false, in: defaults)
        AppSettings.setListeningDetail(.paragraph, in: defaults)
        XCTAssertEqual(defaults.object(forKey: "listening.musicBrainz") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "listening.artwork") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "listening.detail"), "paragraph")

        let preferences = ListeningPreferences.current(in: defaults)
        XCTAssertFalse(preferences.musicBrainz)
        XCTAssertFalse(preferences.showsArtwork)
        XCTAssertEqual(preferences.detail, .paragraph)
    }

    /// The stored names are storage keys: a value another version wrote
    /// and this one doesn't know falls back to the default.
    func testTheDetailsStoredNamesDontChange() {
        XCTAssertEqual(ListeningDetail.allCases.map(\.rawValue), ["one", "three", "paragraph"])
        defaults.set("essay", forKey: "listening.detail")
        XCTAssertEqual(AppSettings.listeningDetail(in: defaults), .threeSentences)
    }

    /// The Music tab sits right after Dictation: the two things Claudio
    /// listens to, side by side.
    func testTheMusicTabSitsAfterDictation() {
        let sections = SettingsSection.allCases
        let dictation = sections.firstIndex(of: .dictation)!
        XCTAssertEqual(sections[dictation + 1], .music)
        XCTAssertEqual(SettingsSection.music.rawValue, "music")
    }
}
