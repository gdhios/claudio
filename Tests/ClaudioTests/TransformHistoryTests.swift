import XCTest
@testable import Claudio

/// The history of free-form instructions: most recent first, no duplicates,
/// capped. This is the value-type core the tests exercise; the store itself
/// only persists it.
final class TransformHistoryTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTheMostRecentIsFirst() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: noon)
        recents = recents.adding("Résume en trois points", at: noon.addingTimeInterval(60))
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Résume en trois points", "Traduis en espagnol"])
    }

    /// Running the same instruction twice doesn't duplicate it: it moves back
    /// to the top, with its new date.
    func testARepeatedInstructionMovesUpWithoutDuplicating() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: noon)
        recents = recents.adding("Passe au passé", at: noon.addingTimeInterval(60))
        recents = recents.adding("Traduis en espagnol", at: noon.addingTimeInterval(120))
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Traduis en espagnol", "Passe au passé"])
        XCTAssertEqual(recents.entries.first?.date, noon.addingTimeInterval(120))
    }

    /// Beyond the cap, the oldest entry falls off.
    func testTheCapDropsTheOldestEntry() {
        var recents = RecentTransforms()
        for i in 1...5 {
            recents = recents.adding("Consigne \(i)", at: noon.addingTimeInterval(Double(i)), limit: 3)
        }
        XCTAssertEqual(recents.entries.map(\.instruction),
                       ["Consigne 5", "Consigne 4", "Consigne 3"])
    }

    /// An empty or blank instruction doesn't enter the history, and text
    /// surrounded by spaces enters it trimmed.
    func testAnEmptyInstructionIsIgnoredAndWhitespaceIsTrimmed() {
        var recents = RecentTransforms()
        recents = recents.adding("   ", at: noon)
        XCTAssertTrue(recents.entries.isEmpty)
        recents = recents.adding("  Traduis en espagnol  ", at: noon)
        XCTAssertEqual(recents.entries.map(\.instruction), ["Traduis en espagnol"])
        // The same instruction, with different spacing, is still a trimmed duplicate.
        recents = recents.adding("Traduis en espagnol", at: noon.addingTimeInterval(60))
        XCTAssertEqual(recents.entries.count, 1)
    }

    func testClearing() {
        var recents = RecentTransforms()
        recents = recents.adding("Traduis en espagnol", at: noon)
        recents = recents.cleared()
        XCTAssertTrue(recents.entries.isEmpty)
    }

    // MARK: - Persistent store

    @MainActor
    func testTheStoreSurvivesARestart() {
        let suite = "ClaudioTests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let magasin = TransformHistory(defaults: defaults, limit: 20)
        magasin.record("Traduis en espagnol", at: noon)
        magasin.record("Résume en trois points", at: noon.addingTimeInterval(60))

        // A new instance, as at the next launch, reads back the same storage.
        let relu = TransformHistory(defaults: defaults, limit: 20)
        XCTAssertEqual(relu.recents.entries.map(\.instruction),
                       ["Résume en trois points", "Traduis en espagnol"])
    }

    @MainActor
    func testClearingTheStoreErasesStorage() {
        let suite = "ClaudioTests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let magasin = TransformHistory(defaults: defaults, limit: 20)
        magasin.record("Traduis en espagnol", at: noon)
        magasin.clear()

        XCTAssertTrue(magasin.recents.entries.isEmpty)
        XCTAssertTrue(TransformHistory(defaults: defaults, limit: 20).recents.entries.isEmpty)
    }

    @MainActor
    func testEmptyStorageStartsEmpty() {
        let defaults = UserDefaults(suiteName: "ClaudioTests.history.\(UUID().uuidString)")!
        XCTAssertTrue(TransformHistory(defaults: defaults, limit: 20).recents.entries.isEmpty)
    }
}
