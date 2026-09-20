import XCTest
@testable import Claudio

/// The `claudio://` links the app answers. Only one so far — a tab of
/// Settings — and that is the point of parsing it as a value: a link that
/// says nothing Claudio knows opens nothing at all, rather than a window at
/// random. Nothing here is a URL the system would hand to another app: the
/// scheme is Claudio's own.
final class ClaudioURLTests: XCTestCase {

    private func parse(_ string: String) -> ClaudioURL? {
        guard let url = URL(string: string) else {
            XCTFail("not a URL: \(string)")
            return nil
        }
        return ClaudioURL.parse(url)
    }

    /// The link the plugin and the website hand out: straight to the tab
    /// where the bridge is switched on.
    func testASectionLinkOpensThatSection() {
        XCTAssertEqual(parse("claudio://settings/streamdeck"), .settings(.streamDeck))
    }

    /// Typed by hand, or capitalized by whatever passed it on: the section
    /// is matched whatever its case.
    func testTheSectionIsMatchedWhateverItsCase() {
        XCTAssertEqual(parse("claudio://settings/STREAMDECK"), .settings(.streamDeck))
    }

    /// Every section of Settings is reachable, by its stored name.
    func testEverySectionIsReachableByName() {
        for section in SettingsSection.allCases {
            XCTAssertEqual(parse("claudio://settings/\(section.rawValue)"), .settings(section))
        }
    }

    /// No section named: Settings opens where it always opens.
    func testSettingsWithNoSectionOpensTheGeneralOne() {
        XCTAssertEqual(parse("claudio://settings"), .settings(.general))
    }

    /// A tab that doesn't exist — a typo, or a link from a later version:
    /// better nothing than the wrong tab.
    func testAnUnknownSectionOpensNothing() {
        XCTAssertNil(parse("claudio://settings/nope"))
    }

    /// Claudio's own scheme, and no other: a web address is the browser's
    /// business, even when it points at Claudio's site.
    func testAnotherSchemeOpensNothing() {
        XCTAssertNil(parse("https://claudio.okonoma.com/#streamdeck"))
    }

    /// The scheme is ours, the rest isn't understood: nothing opens.
    func testAnUnknownLinkOpensNothing() {
        XCTAssertNil(parse("claudio://other"))
    }
}
