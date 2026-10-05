import XCTest
@testable import Claudio

/// What the clock posts to its button callback: a press (`state:true`) and
/// a release, for each of its three buttons, the two arriving in either
/// order. The hub acts on the middle one going down, and on nothing else.
final class UlanziButtonReportTests: XCTestCase {

    private func isMiddlePress(_ json: String) -> Bool {
        UlanziButtonReport.isMiddlePress(Data(json.utf8))
    }

    func testTheMiddleButtonGoingDownIsAPress() {
        XCTAssertTrue(isMiddlePress(#"{"button":"middle","state":true,"uid":"awtrix_1a2b3c"}"#))
    }

    /// Its release is not: the press and the release come within the same
    /// second, and only one of them may act.
    func testTheReleaseIsIgnored() {
        XCTAssertFalse(isMiddlePress(#"{"button":"middle","state":false,"uid":"awtrix_1a2b3c"}"#))
    }

    func testTheOtherButtonsAreIgnored() {
        XCTAssertFalse(isMiddlePress(#"{"button":"left","state":true}"#))
        XCTAssertFalse(isMiddlePress(#"{"button":"right","state":true}"#))
    }

    func testAReportWithoutButtonOrStateIsIgnored() {
        XCTAssertFalse(isMiddlePress(#"{"button":"middle"}"#))
        XCTAssertFalse(isMiddlePress(#"{"state":true}"#))
        XCTAssertFalse(isMiddlePress(#"{"button":"middle","state":"true"}"#))
        XCTAssertFalse(isMiddlePress("not json"))
    }
}
