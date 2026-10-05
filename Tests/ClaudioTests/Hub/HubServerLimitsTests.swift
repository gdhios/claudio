import XCTest
@testable import Claudio

/// The server's limits, as decided. A request may carry a mebibyte: a Stop
/// brings the turn's last message whole, and losing an alert is worse than
/// holding a bigger buffer. It has two seconds to arrive, and sixteen
/// connections are held at most.
@MainActor
final class HubServerLimitsTests: XCTestCase {

    func testARequestMayCarryAMebibyte() {
        XCTAssertEqual(HubServer.maximumRequestSize, 1_048_576)
    }

    func testARequestHasTwoSecondsToArrive() {
        XCTAssertEqual(HubServer.receiveTimeout, .seconds(2))
    }

    func testSixteenConnectionsAreHeldAtMost() {
        XCTAssertEqual(HubServer.maximumConnections, 16)
    }
}
