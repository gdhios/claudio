import XCTest
@testable import Claudio

/// A crash of an earlier build mid-dictation left its mute tap behind, and
/// with it every app silenced. At launch the tap is found by its name and
/// removed — Claudio's own, and nobody else's.
final class LeftoverMuteTapsTests: XCTestCase {

    func testOnlyClaudiosOwnTapsAreLeftovers() {
        let taps: [(id: UInt32, name: String?)] = [
            (12, LeftoverMuteTaps.tapName),
            (13, "Some recorder's tap"),
            (14, nil),
            (15, LeftoverMuteTaps.tapName),
        ]
        XCTAssertEqual(LeftoverMuteTaps.leftovers(among: taps), [12, 15])
    }

    /// The name earlier builds gave their tap, byte for byte: changed, the
    /// sweep would find nothing to remove.
    func testTheTapIsLookedForUnderTheNameEarlierBuildsGaveIt() {
        XCTAssertEqual(LeftoverMuteTaps.tapName, "Claudio dictation mute")
    }
}
