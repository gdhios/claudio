import XCTest
import CoreGraphics
@testable import Claudio

/// The one impure detail the mover needs, isolated as a value: converting a
/// Cocoa rect (bottom-left origin, y up) to Accessibility coordinates
/// (top-left origin, y down), across displays, using the primary display height.
final class ScreenGeometryTests: XCTestCase {
    func testAMainScreenVisibleFrameFlipsToTheMenuBarInset() {
        // 1440×900 primary, 24 pt menu bar: Cocoa visibleFrame sits at y = 0.
        let cocoa = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let ax = ScreenGeometry.axRect(fromCocoa: cocoa, primaryHeight: 900)
        XCTAssertEqual(ax, CGRect(x: 0, y: 24, width: 1440, height: 876))
    }

    func testAnOffsetRectFlipsAroundThePrimaryHeight() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = ScreenGeometry.axRect(fromCocoa: cocoa, primaryHeight: 900)
        // axY = 900 - (200 + 400) = 300.
        XCTAssertEqual(ax, CGRect(x: 100, y: 300, width: 300, height: 400))
    }
}

/// Moving a window to another display, as pure geometry: which usable area
/// comes next in the cycle, and what frame keeps the window's placement there.
/// All rects are in AX coordinates.
final class ScreenSwitchGeometryTests: XCTestCase {
    /// 1440×900 primary on the left, menu bar included; 1920×1080 on its right.
    private let left = CGRect(x: 0, y: 24, width: 1440, height: 876)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    private func assertRect(_ got: CGRect, _ expected: CGRect,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.minX, expected.minX, accuracy: 0.01, "minX", file: file, line: line)
        XCTAssertEqual(got.minY, expected.minY, accuracy: 0.01, "minY", file: file, line: line)
        XCTAssertEqual(got.width, expected.width, accuracy: 0.01, "width", file: file, line: line)
        XCTAssertEqual(got.height, expected.height, accuracy: 0.01, "height", file: file, line: line)
    }

    // MARK: - Which display comes next

    func testTwoDisplaysCycleBackAndForth() {
        XCTAssertEqual(ScreenGeometry.next(after: left, in: [left, right]), right)
        XCTAssertEqual(ScreenGeometry.next(after: right, in: [left, right]), left)
    }

    /// The cycle follows the physical arrangement, left to right, not the order
    /// macOS happens to report the displays in.
    func testThreeDisplaysAreOrderedByTheirLeftEdge() {
        let far = CGRect(x: 3360, y: 0, width: 1280, height: 800)
        let unordered = [right, far, left]
        XCTAssertEqual(ScreenGeometry.next(after: left, in: unordered), right)
        XCTAssertEqual(ScreenGeometry.next(after: right, in: unordered), far)
        XCTAssertEqual(ScreenGeometry.next(after: far, in: unordered), left)
    }

    func testASingleDisplayHasNoNextOne() {
        XCTAssertNil(ScreenGeometry.next(after: left, in: [left]))
    }

    func testAnUnknownCurrentDisplayHasNoNextOne() {
        let elsewhere = CGRect(x: 9000, y: 0, width: 100, height: 100)
        XCTAssertNil(ScreenGeometry.next(after: elsewhere, in: [left, right]))
    }

    // MARK: - Keeping the placement across displays

    /// A half stays a half, a quarter a quarter: the placement is read as a
    /// fraction of the source area and rewritten as the same fraction of the
    /// target, whatever the two displays' sizes and ratios.
    func testALeftHalfStaysALeftHalfOnABiggerDisplay() {
        let half = CGRect(x: 0, y: 24, width: 720, height: 876)
        assertRect(ScreenGeometry.reproject(half, from: left, to: right),
                   CGRect(x: 1440, y: 0, width: 960, height: 1080))
    }

    func testAMaximizedWindowStaysMaximized() {
        assertRect(ScreenGeometry.reproject(left, from: left, to: right), right)
        assertRect(ScreenGeometry.reproject(right, from: right, to: left), left)
    }

    func testABottomRightQuarterStaysInTheBottomRightCorner() {
        let quarter = CGRect(x: 720, y: 462, width: 720, height: 438)
        assertRect(ScreenGeometry.reproject(quarter, from: left, to: right),
                   CGRect(x: 2400, y: 540, width: 960, height: 540))
    }

    /// A free-floating window keeps its relative position and is scaled by the
    /// ratio between the two areas.
    func testAFloatingWindowKeepsItsRelativePosition() {
        let window = CGRect(x: 360, y: 243, width: 360, height: 438)
        // x: 360/1440 = 25% → 1440 + 480 ; y: (243-24)/876 = 25% → 270.
        assertRect(ScreenGeometry.reproject(window, from: left, to: right),
                   CGRect(x: 1920, y: 270, width: 480, height: 540))
    }

    /// Like `WindowLayout.center`, the top-left never lands outside the target
    /// area: a window that overflowed its display stays grabbable on the next.
    func testAnOverflowingWindowKeepsItsTopLeftInside() {
        let overflowing = CGRect(x: -200, y: -100, width: 800, height: 600)
        let got = ScreenGeometry.reproject(overflowing, from: left, to: right)
        XCTAssertEqual(got.minX, right.minX, accuracy: 0.01)
        XCTAssertEqual(got.minY, right.minY, accuracy: 0.01)
    }

    /// A display can't report an empty usable area, but the division must not
    /// be the thing that decides: the window then simply lands at the corner.
    func testAnEmptySourceAreaPutsTheWindowAtTheTargetCorner() {
        let empty = CGRect(x: 0, y: 0, width: 0, height: 0)
        let window = CGRect(x: 10, y: 10, width: 300, height: 200)
        assertRect(ScreenGeometry.reproject(window, from: empty, to: right),
                   CGRect(x: 1440, y: 0, width: 300, height: 200))
    }
}
