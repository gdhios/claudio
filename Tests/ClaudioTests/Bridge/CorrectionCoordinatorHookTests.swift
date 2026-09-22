import XCTest
@testable import Claudio

/// The hook the Stream Deck bridge watches a correction through. Only what a
/// coordinator does with no session is playable here: starting one needs the
/// Accessibility permission and a real selection, which no test may ask for,
/// and nothing outside the coordinator can hand it a session. The announcement
/// of a real one is proved on the dictation side, whose coordinator plays
/// without a microphone; here, `DictationCoordinatorTests` is the witness.
@MainActor
final class CorrectionCoordinatorHookTests: XCTestCase {

    /// `dismiss()` is idempotent and gets called on every trigger before
    /// anything else. With nothing on screen it has no news, and says none:
    /// a bridge redrawing a key on each keystroke would be paying for it.
    func testDismissingOverNothingAnnouncesNothing() {
        let coordinator = CorrectionCoordinator()
        var announced: [CorrectionSession?] = []
        coordinator.onSessionChange = { announced.append($0) }

        coordinator.dismiss()
        coordinator.dismiss()
        XCTAssertTrue(announced.isEmpty)
        XCTAssertNil(coordinator.session)
    }

    /// Nothing is announced for a hook that was never set: the coordinator
    /// runs the same with or without a bridge listening.
    func testACoordinatorWithNoHookDismissesAllTheSame() {
        let coordinator = CorrectionCoordinator()
        coordinator.dismiss()
        XCTAssertNil(coordinator.session)
    }
}
