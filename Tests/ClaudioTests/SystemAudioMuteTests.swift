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

    /// The watchdog gives the sound back when no way out of a dictation did.
    /// It must never be what ends the silence of one still under way: a
    /// locked dictation keeps the apps quiet from its press, through the tap,
    /// to its own limit.
    @MainActor
    func testTheWatchdogOutlastsTheLongestLockedDictation() {
        let tap = Duration.milliseconds(Int(DictationCoordinator.shortPressThreshold * 1000))
        XCTAssertGreaterThan(SystemAudioMute.longestSilence,
                             DictationCoordinator.longestLockedDictation + tap)
    }
}
