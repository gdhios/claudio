import XCTest
@testable import Claudio

/// Automatic updates hinge on two decisions: "is this version newer?" and
/// "is this version.json readable?". A mistake here either offers an update
/// in a loop, or never offers one again.
final class UpdateCheckerTests: XCTestCase {

    func testNewerOnlyIfStrictlyAbove() {
        XCTAssertTrue(UpdateChecker.isNewer("1.5.1", than: "1.5.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.5.1", than: "1.5.1"), "equal version: nothing to offer")
        XCTAssertFalse(UpdateChecker.isNewer("1.4.9", than: "1.5.0"), "stale feed: no rolling back")
    }

    /// The ordering is numeric, not alphabetical: the day 1.10 ships, it must
    /// rank above 1.9 (alphabetically, "1.10" < "1.9").
    func testTheComparisonIsNumeric() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.9", than: "1.10.0"))
    }

    /// The exact format the release chain writes to the server: if one
    /// side changes without the other, no one gets notified of updates
    /// anymore.
    @MainActor
    func testTheFeedWrittenByTheReleaseScriptDecodes() throws {
        let json = Data(#"{"version":"1.5.1","url":"https://claudio.okonoma.com/Claudio.zip"}"#.utf8)
        let feed = try JSONDecoder().decode(UpdateChecker.Feed.self, from: json)
        XCTAssertEqual(feed.version, "1.5.1")
        XCTAssertEqual(feed.url, URL(string: "https://claudio.okonoma.com/Claudio.zip"))
    }

    /// An incomplete feed must not pass as valid: `checkNow` turns it into
    /// `.failed`, never into "up to date".
    @MainActor
    func testAnIncompleteFeedIsRejected() {
        let sansURL = Data(#"{"version":"1.5.1"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateChecker.Feed.self, from: sansURL))
    }
}
