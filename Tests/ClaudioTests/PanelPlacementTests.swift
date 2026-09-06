import XCTest
import AppKit
@testable import Claudio

/// The panel always opens centered on the active screen (never in a corner,
/// never overflowing), and it stays centered as its height follows the content.
final class PanelCenteringTests: XCTestCase {
    /// A 1920×1080 screen with its menu bar: what `visibleFrame` sees.
    private let visible = NSRect(x: 0, y: 52, width: 1920, height: 998)

    func testThePanelIsCentered() {
        let placed = ResultPanel.centered(size: NSSize(width: 460, height: 200), in: visible)
        XCTAssertEqual(placed.midX, visible.midX, accuracy: 0.01)
        XCTAssertEqual(placed.midY, visible.midY, accuracy: 0.01)
    }

    /// Every possible height, from the welcome panel to the full palette,
    /// stays centered on the same midpoint: it grows without sliding.
    func testTheMidpointDoesNotMoveWhenHeightChanges() {
        for height in stride(from: 180.0, through: 900.0, by: 30.0) {
            let placed = ResultPanel.centered(size: NSSize(width: 460, height: height), in: visible)
            XCTAssertEqual(placed.midX, visible.midX, accuracy: 0.01, "height \(height)")
            XCTAssertEqual(placed.midY, visible.midY, accuracy: 0.01, "height \(height)")
        }
    }

    func testThePanelStaysOnScreen() {
        for height in [180.0, 300.0, 560.0, 900.0] {
            let placed = ResultPanel.centered(size: NSSize(width: 460, height: height), in: visible)
            XCTAssertTrue(visible.contains(placed), "frame off-screen for height \(height)")
        }
    }

    /// On a second screen (offset origin), the targeted center is that
    /// screen's own, not the main screen's.
    func testCenteringOnTheGivenScreen() {
        let autre = NSRect(x: 1920, y: 0, width: 1440, height: 900)
        let placed = ResultPanel.centered(size: NSSize(width: 460, height: 200), in: autre)
        XCTAssertEqual(placed.midX, autre.midX, accuracy: 0.01)
        XCTAssertEqual(placed.midY, autre.midY, accuracy: 0.01)
    }
}

/// While streaming, the text grows one notch at a time: the window follows
/// these small steps instantly, frame by frame, and slides with an easeOut
/// only on the big jumps (opening, switching to the palette or to an error).
/// Without this split, an easeOut on every notch would make the growth jerky.
final class PanelResizeAnimationTests: XCTestCase {
    func testASmallStepFollowsTheTextWithoutAnimating() {
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 200, to: 200))
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 200, to: 224),
                       "one more line is followed instantly, not animated")
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 300, to: 260))
    }

    func testABigJumpAnimates() {
        XCTAssertTrue(ResultPanel.shouldAnimateResize(from: 200, to: 460),
                      "opening a long result slides instead of snapping")
        XCTAssertTrue(ResultPanel.shouldAnimateResize(from: 480, to: 210),
                      "returning to a small size also slides")
    }
}

/// Hovering the palette only selects once the pointer is actually moving.
@MainActor
final class PaletteHoverTests: XCTestCase {
    private func palette() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "un texte"
        session.phase = .choosingAction
        return session
    }

    func testHoverWithNoMovementSelectsNothing() {
        let session = palette()
        session.armHover(at: CGPoint(x: 500, y: 400))
        XCTAssertFalse(session.acceptsHover(at: CGPoint(x: 500, y: 400)))
        XCTAssertFalse(session.acceptsHover(at: CGPoint(x: 501, y: 400)))  // jitter
    }

    func testHoverCountsOncePointerMoves() {
        let session = palette()
        session.armHover(at: CGPoint(x: 500, y: 400))
        XCTAssertTrue(session.acceptsHover(at: CGPoint(x: 500, y: 460)))
        // The pointer has moved: the mouse resumes its job for good.
        XCTAssertTrue(session.acceptsHover(at: CGPoint(x: 500, y: 460)))
    }

    func testHoverCountsWhenNothingHasArmedTheGuard() {
        XCTAssertTrue(palette().acceptsHover(at: CGPoint(x: 0, y: 0)))
    }
}
