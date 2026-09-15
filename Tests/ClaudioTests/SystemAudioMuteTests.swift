import XCTest
@testable import Claudio

/// A crash mid-dictation leaves Claudio's tap behind, and with it every app
/// silenced. At the next launch the tap is found by its name and removed —
/// Claudio's own, and nobody else's.
final class SystemAudioMuteTests: XCTestCase {

    func testOnlyClaudiosOwnTapsAreLeftovers() {
        let taps: [(id: UInt32, name: String?)] = [
            (12, SystemAudioMute.tapName),
            (13, "Some recorder's tap"),
            (14, nil),
            (15, SystemAudioMute.tapName),
        ]
        XCTAssertEqual(SystemAudioMute.leftovers(among: taps), [12, 15])
    }
}
