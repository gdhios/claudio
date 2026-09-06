import XCTest
import CoreGraphics
@testable import Claudio

/// Pure geometry of the window layouts: given the screen's usable area and the
/// window's current frame, where does each layout put it? All rects use the
/// Accessibility convention (top-left origin, y growing downward), so the code
/// under test never touches a screen or a flip — it stays a value.
final class WindowLayoutTests: XCTestCase {
    /// A 1440×900 screen with a 24 pt menu bar: usable area in AX coordinates.
    private let visible = CGRect(x: 0, y: 24, width: 1440, height: 876)
    /// An arbitrary window; only `center` reads its size.
    private let current = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func assertFrame(_ layout: WindowLayout,
                             equals expected: CGRect,
                             _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let got = layout.frame(in: visible, current: current)
        XCTAssertEqual(got.minX, expected.minX, accuracy: 0.01, "minX \(message)", file: file, line: line)
        XCTAssertEqual(got.minY, expected.minY, accuracy: 0.01, "minY \(message)", file: file, line: line)
        XCTAssertEqual(got.width, expected.width, accuracy: 0.01, "width \(message)", file: file, line: line)
        XCTAssertEqual(got.height, expected.height, accuracy: 0.01, "height \(message)", file: file, line: line)
    }

    // MARK: - Halves

    func testLeftHalfTakesTheLeftColumn() {
        assertFrame(.leftHalf, equals: CGRect(x: 0, y: 24, width: 720, height: 876))
    }

    func testRightHalfTakesTheRightColumn() {
        assertFrame(.rightHalf, equals: CGRect(x: 720, y: 24, width: 720, height: 876))
    }

    func testTopHalfTakesTheUpperRow() {
        assertFrame(.topHalf, equals: CGRect(x: 0, y: 24, width: 1440, height: 438))
    }

    func testBottomHalfTakesTheLowerRow() {
        assertFrame(.bottomHalf, equals: CGRect(x: 0, y: 462, width: 1440, height: 438))
    }

    // MARK: - Quarters

    func testTopLeftQuarter() {
        assertFrame(.topLeft, equals: CGRect(x: 0, y: 24, width: 720, height: 438))
    }

    func testTopRightQuarter() {
        assertFrame(.topRight, equals: CGRect(x: 720, y: 24, width: 720, height: 438))
    }

    func testBottomLeftQuarter() {
        assertFrame(.bottomLeft, equals: CGRect(x: 0, y: 462, width: 720, height: 438))
    }

    func testBottomRightQuarter() {
        assertFrame(.bottomRight, equals: CGRect(x: 720, y: 462, width: 720, height: 438))
    }

    // MARK: - Maximize

    func testMaximizeFillsTheUsableArea() {
        assertFrame(.maximize, equals: visible)
    }

    // MARK: - Center

    func testCenterKeepsTheSizeAndCentersInside() {
        // x = (1440 - 400) / 2 = 520 ; y = 24 + (876 - 300) / 2 = 312.
        assertFrame(.center, equals: CGRect(x: 520, y: 312, width: 400, height: 300))
    }

    /// A window larger than the screen keeps its top-left inside the usable
    /// area rather than centering with a negative offset, so its title bar
    /// stays reachable; it may overflow to the right and bottom.
    func testCenterClampsAnOversizedWindowToTheTopLeft() {
        let oversized = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let got = WindowLayout.center.frame(in: visible, current: oversized)
        XCTAssertEqual(got.minX, visible.minX, accuracy: 0.01)
        XCTAssertEqual(got.minY, visible.minY, accuracy: 0.01)
        XCTAssertEqual(got.width, 2000, accuracy: 0.01)
        XCTAssertEqual(got.height, 1000, accuracy: 0.01)
    }
}

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
