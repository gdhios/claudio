import XCTest
@testable import Claudio

/// The hook the bridges watch a correction through: the app sets it once and
/// tells both, the Stream Deck's and the Ulanzi's. Only what a coordinator
/// does with no session is played here; a whole correction, run on fakes, is
/// `CorrectionCoordinatorTests`'s. The announcement of a real session is
/// proved on the dictation side, whose hook is the same broadcast; here,
/// `DictationCoordinatorTests` is the witness.
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
