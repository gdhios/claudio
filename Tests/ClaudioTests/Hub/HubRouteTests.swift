import XCTest
@testable import Claudio

/// The two ways into the hub, both ending in the launch's token, and the
/// answer to everything else: 404, a wrong token included, so that nothing
/// says a path exists. A route whose body is no JSON object is answered 400
/// and goes no further.
final class HubRouteTests: XCTestCase {

    private let token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private let body = Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)

    private func match(_ method: String, _ path: String) -> HubRoute? {
        HubRoute.match(method: method, path: path, token: token, body: body)
    }

    // MARK: - Matching

    /// The relay's events and the clock's buttons, with the right token,
    /// carry their body on.
    func testTheTwoRoutesWithTheRightToken() {
        XCTAssertEqual(match("POST", "/claude-code/\(token)"), .hookEvent(body))
        XCTAssertEqual(match("POST", "/ulanzi/button/\(token)"), .button(body))
    }

    /// Another token, part of it, or more than it: nothing there.
    func testAWrongTokenIsNoRoute() {
        let other = String(token.reversed())
        XCTAssertNil(match("POST", "/claude-code/\(other)"))
        XCTAssertNil(match("POST", "/ulanzi/button/\(other)"))
        XCTAssertNil(match("POST", "/claude-code/\(token.prefix(63))"))
        XCTAssertNil(match("POST", "/claude-code/\(token)/"))
        XCTAssertNil(match("POST", "/claude-code/\(token)/x"))
        XCTAssertNil(match("POST", "/claude-code/"))
    }

    /// A hub without a token lets nobody in, the empty token included.
    func testAnEmptyTokenOpensNothing() {
        XCTAssertNil(HubRoute.match(method: "POST", path: "/claude-code/", token: "", body: body))
    }

    /// Only a POST is a route.
    func testAnotherMethodIsNoRoute() {
        for method in ["GET", "PUT", "DELETE", "post"] {
            XCTAssertNil(match(method, "/claude-code/\(token)"), method)
            XCTAssertNil(match(method, "/ulanzi/button/\(token)"), method)
        }
    }

    /// Any other path, the token or not.
    func testAnUnknownPathIsNoRoute() {
        for path in ["/", "/claude-code", "/ulanzi/\(token)", "/ulanzi/buttons/\(token)", "/\(token)",
                     "/api/v1/claude-code/\(token)"] {
            XCTAssertNil(match("POST", path), path)
        }
    }

    // MARK: - Answering

    private func answer(_ method: String, _ path: String, body: String) -> (status: Int, route: HubRoute?) {
        HubRoute.answer(HubRequest(method: method, path: path, body: Data(body.utf8)), token: token)
    }

    /// A route with a JSON object goes on, answered 200.
    func testARouteWithAnObjectIsAnswered200() {
        let reply = answer("POST", "/ulanzi/button/\(token)", body: #"{"button":"middle","state":true}"#)

        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.route, .button(Data(#"{"button":"middle","state":true}"#.utf8)))
    }

    /// No route: 404, and nothing goes on.
    func testNoRouteIsAnswered404() {
        let reply = answer("POST", "/claude-code/wrong", body: "{}")

        XCTAssertEqual(reply.status, 404)
        XCTAssertNil(reply.route)
    }

    /// A body missing, not JSON, or JSON that is no object: 400, ignored.
    func testABodyThatIsNoObjectIsAnswered400() {
        for body in ["", "{not json", #"["Stop"]"#, "42"] {
            let reply = answer("POST", "/claude-code/\(token)", body: body)
            XCTAssertEqual(reply.status, 400, body)
            XCTAssertNil(reply.route, body)
        }
    }

    // MARK: - The answer on the wire

    /// Always short, JSON, and closing.
    func testTheAnswerIsShortAndCloses() {
        XCTAssertEqual(String(decoding: HubResponse.data(status: 200), as: UTF8.self),
                       "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n"
                        + "Connection: close\r\n\r\n{\"ok\":true}")
        XCTAssertEqual(String(decoding: HubResponse.data(status: 404), as: UTF8.self),
                       "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 12\r\n"
                        + "Connection: close\r\n\r\n{\"ok\":false}")
        XCTAssertTrue(String(decoding: HubResponse.data(status: 400), as: UTF8.self)
            .hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        XCTAssertTrue(String(decoding: HubResponse.data(status: 413), as: UTF8.self)
            .hasPrefix("HTTP/1.1 413 Content Too Large\r\n"))
    }
}
