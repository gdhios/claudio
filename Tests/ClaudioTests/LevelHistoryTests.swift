import XCTest
@testable import Claudio

/// The last few loudness readings, oldest first: what the waveform draws,
/// one bar per reading, sliding along as new ones come in.
final class LevelHistoryTests: XCTestCase {

    func testItStartsFlat() {
        XCTAssertEqual(LevelHistory(count: 4).values, [0, 0, 0, 0])
    }

    func testANewReadingGoesAtTheEndAndTheOldestDrops() {
        let history = LevelHistory(count: 3).adding(0.2).adding(0.5).adding(0.9).adding(0.4)
        XCTAssertEqual(history.values, [0.5, 0.9, 0.4])
    }

    func testReadingsAreKeptBetweenZeroAndOne() {
        let history = LevelHistory(count: 2).adding(-0.3).adding(1.7)
        XCTAssertEqual(history.values, [0, 1])
    }
}
