import XCTest
@testable import Claudio

/// The size setting touches two irreversible things: the keys written to
/// UserDefaults, and the panel's look for whoever never touches it.
final class PanelTextSizeTests: XCTestCase {

    /// The rawValues are storage keys: renaming them would lose the setting
    /// of everyone who chose one.
    func testTheStoredIdentifiersDontChange() {
        XCTAssertEqual(PanelTextSize.allCases.map(\.rawValue),
                       ["small", "normal", "large", "extraLarge"])
    }

    /// The default setting must leave the panel exactly as it was before.
    func testTheNormalSettingChangesNothing() {
        let normal = PanelTextSize.normal
        XCTAssertEqual(normal.scale, 1)
        XCTAssertEqual(normal.points(12.2), 12.2)
        XCTAssertEqual(normal.panelWidth, Constants.panelWidth)
        XCTAssertEqual(normal.maxTextHeight, Constants.panelMaxTextHeight)
    }

    /// Body size, width, and height grow together, from small to extra large.
    func testEverythingGrowsInTheSameDirection() {
        let ordered = PanelTextSize.allCases
        for (petit, grand) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(petit.bodyPoints, grand.bodyPoints, "\(petit) → \(grand)")
            XCTAssertLessThanOrEqual(petit.panelWidth, grand.panelWidth, "\(petit) → \(grand)")
            XCTAssertLessThanOrEqual(petit.maxTextHeight, grand.maxTextHeight, "\(petit) → \(grand)")
        }
    }

    /// A small body size must not shrink the panel: the text would gain
    /// longer lines without anyone asking for it.
    func testASmallBodySizeDoesNotShrinkThePanel() {
        XCTAssertEqual(PanelTextSize.small.panelWidth, Constants.panelWidth)
        XCTAssertEqual(PanelTextSize.small.maxTextHeight, Constants.panelMaxTextHeight)
    }

    /// The panel stays a panel: the text area is capped even at the largest
    /// body size, otherwise it would spill off small screens.
    func testTheTextAreaStaysBounded() {
        for size in PanelTextSize.allCases {
            XCTAssertLessThanOrEqual(size.maxTextHeight, 520, size.rawValue)
        }
    }

    /// A missing setting, or one written by a version we don't know: fall
    /// back to the normal body size rather than an empty panel.
    func testAnUnknownSettingFallsBackToNormal() {
        let key = "panelTextSize"
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(AppSettings.panelTextSize, .normal)

        defaults.set("gigantesque", forKey: key)
        XCTAssertEqual(AppSettings.panelTextSize, .normal)

        AppSettings.panelTextSize = .extraLarge
        XCTAssertEqual(AppSettings.panelTextSize, .extraLarge)
        XCTAssertEqual(defaults.string(forKey: key), "extraLarge")
    }
}
