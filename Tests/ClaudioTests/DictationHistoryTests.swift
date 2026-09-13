import XCTest
@testable import Claudio

/// The dictation history: most recent first, capped, raw text always kept
/// next to the cleaned one. The value type is what the tests exercise; the
/// store only persists it, under its own key.
final class DictationHistoryTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func dictation(_ raw: String,
                           cleaned: String? = nil,
                           at date: Date,
                           language: DictationLanguage = .frFR) -> RecentDictation {
        RecentDictation(date: date, language: language, raw: raw, cleaned: cleaned)
    }

    // MARK: - The value

    func testTheMostRecentIsFirst() {
        var recents = RecentDictations()
        recents = recents.adding(dictation("bonjour", at: noon))
        recents = recents.adding(dictation("bonsoir", at: noon.addingTimeInterval(60)))
        XCTAssertEqual(recents.entries.map(\.raw), ["bonsoir", "bonjour"])
    }

    /// The same words twice are two dictations, unlike a repeated custom
    /// instruction: what is kept here is what was said, each time.
    func testTheSameWordsTwiceAreTwoEntries() {
        var recents = RecentDictations()
        recents = recents.adding(dictation("bonjour", at: noon))
        recents = recents.adding(dictation("bonjour", at: noon.addingTimeInterval(60)))
        XCTAssertEqual(recents.entries.count, 2)
        XCTAssertEqual(recents.entries.first?.date, noon.addingTimeInterval(60))
    }

    /// Beyond the cap, the oldest entry falls off. The cap is 50 by default.
    func testTheCapDropsTheOldestEntry() {
        var recents = RecentDictations()
        for i in 1...5 {
            recents = recents.adding(dictation("Dictée \(i)", at: noon.addingTimeInterval(Double(i))),
                                     limit: 3)
        }
        XCTAssertEqual(recents.entries.map(\.raw), ["Dictée 5", "Dictée 4", "Dictée 3"])

        var fifty = RecentDictations()
        for i in 1...60 {
            fifty = fifty.adding(dictation("Dictée \(i)", at: noon.addingTimeInterval(Double(i))))
        }
        XCTAssertEqual(fifty.entries.count, 50)
        XCTAssertEqual(fifty.entries.first?.raw, "Dictée 60")
        XCTAssertEqual(fifty.entries.last?.raw, "Dictée 11")
    }

    /// A short press, a silence: the engine returns nothing. Nothing is
    /// recorded, and surrounding whitespace is trimmed off what is.
    func testABlankRawIsIgnoredAndWhitespaceIsTrimmed() {
        var recents = RecentDictations()
        recents = recents.adding(dictation("   \n ", at: noon))
        XCTAssertTrue(recents.entries.isEmpty)
        recents = recents.adding(dictation("  bonjour  ", cleaned: "  Bonjour.  ", at: noon))
        XCTAssertEqual(recents.entries.map(\.raw), ["bonjour"])
        XCTAssertEqual(recents.entries.first?.cleaned, "Bonjour.")
    }

    /// Pasted raw ("Raw" model, or a cleanup that failed): the entry holds
    /// the transcript and no cleaned version, rather than a copy of itself.
    func testAnEntryWithoutCleanupHoldsOnlyTheRaw() {
        var recents = RecentDictations()
        recents = recents.adding(dictation("bonjour", cleaned: "   ", at: noon))
        XCTAssertEqual(recents.entries.first?.raw, "bonjour")
        XCTAssertNil(recents.entries.first?.cleaned)
    }

    func testClearing() {
        var recents = RecentDictations()
        recents = recents.adding(dictation("bonjour", at: noon))
        XCTAssertTrue(recents.cleared().entries.isEmpty)
    }

    /// The raw text, the cleaned one, the language and the date all survive
    /// a round trip through JSON: that is what the store writes.
    func testAnEntrySurvivesEncoding() throws {
        let entry = dictation("bonjour tout le monde", cleaned: "Bonjour tout le monde.",
                              at: noon, language: .enGB)
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([RecentDictation].self, from: data)
        XCTAssertEqual(decoded, [entry])
        XCTAssertEqual(decoded.first?.language, DictationLanguage.enGB.rawValue)
    }

    // MARK: - Persistent store

    @MainActor
    func testTheStoreSurvivesARestart() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!

        let history = DictationHistory(defaults: defaults)
        history.record(raw: "bonjour", cleaned: "Bonjour.", language: .frFR, at: noon)
        history.record(raw: "good evening", cleaned: nil, language: .enUS,
                       at: noon.addingTimeInterval(60))

        // A new instance, as at the next launch, reads back the same storage.
        let reread = DictationHistory(defaults: defaults)
        XCTAssertEqual(reread.recents.entries.map(\.raw), ["good evening", "bonjour"])
        XCTAssertEqual(reread.recents.entries.first?.language, DictationLanguage.enUS.rawValue)
        XCTAssertNil(reread.recents.entries.first?.cleaned)
        XCTAssertEqual(reread.recents.entries.last?.cleaned, "Bonjour.")
        // Written under the key the design names, and nowhere else.
        XCTAssertNotNil(defaults.data(forKey: "dictationHistory"))
    }

    @MainActor
    func testClearingTheStoreErasesStorage() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!

        let history = DictationHistory(defaults: defaults)
        history.record(raw: "bonjour", cleaned: nil, language: .frFR, at: noon)
        history.clear()

        XCTAssertTrue(history.recents.entries.isEmpty)
        XCTAssertTrue(DictationHistory(defaults: defaults).recents.entries.isEmpty)
    }

    /// Nothing heard: the store writes nothing at all.
    @MainActor
    func testABlankDictationIsNotStored() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!

        let history = DictationHistory(defaults: defaults)
        history.record(raw: "  ", cleaned: nil, language: .frFR, at: noon)

        XCTAssertTrue(history.recents.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: "dictationHistory"))
    }

    @MainActor
    func testEmptyStorageStartsEmpty() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!
        XCTAssertTrue(DictationHistory(defaults: defaults).recents.entries.isEmpty)
    }
}
