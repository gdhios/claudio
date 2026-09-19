import XCTest
@testable import Claudio

/// The hook the Stream Deck bridge watches a correction through. Only the
/// closing half is playable here: starting one needs the Accessibility
/// permission and a real selection, which no test may ask for. The panel
/// leaving the screen is the half that breaks silently — a key still showing
/// a face over a panel that closed — so that is the one pinned down.
@MainActor
final class CorrectionCoordinatorHookTests: XCTestCase {

    func testTheEndOfAPanelIsAnnouncedAsNoSession() {
        let coordinator = CorrectionCoordinator()
        var announced: [CorrectionSession?] = []
        coordinator.onSessionChange = { announced.append($0) }
        XCTAssertTrue(announced.isEmpty)

        coordinator.dismiss()
        XCTAssertEqual(announced.count, 1)
        XCTAssertNil(announced.last ?? nil)
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
