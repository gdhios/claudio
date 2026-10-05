import XCTest
@testable import Claudio

/// A request to the hub as it comes off the wire, read as a value: the
/// request line, the headers up to the blank line, then `Content-Length`
/// bytes of body. No socket is opened.
final class HubRequestTests: XCTestCase {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    /// The relay's request, whole: the method, the path, and the body as it
    /// was sent, accents and squares included.
    func testACompleteRequestIsReadWhole() throws {
        let body = #"{"hook_event_name":"Stop","last_assistant_message":"🟧 DÉCISION"}"#
        let request = try XCTUnwrap(HubRequest.parse(data(
            "POST /claude-code/abc HTTP/1.1\r\nHost: 127.0.0.1:51234\r\nContent-Type: application/json\r\n"
                + "Content-Length: \(body.utf8.count)\r\n\r\n\(body)")))

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/claude-code/abc")
        XCTAssertEqual(request.body, data(body))
    }

    /// The clock's request, as its HTTP client writes it.
    func testTheClocksRequestIsReadToo() throws {
        let body = #"{"button":"middle","state":true,"uid":"awtrix_1a2b3c"}"#
        let request = try XCTUnwrap(HubRequest.parse(data(
            "POST /ulanzi/button/abc HTTP/1.1\r\nHost: 192.168.1.50:51234\r\nUser-Agent: ESP32HTTPClient\r\n"
                + "Connection: keep-alive\r\nAccept-Encoding: identity;q=1,chunked;q=0.1,*;q=0\r\n"
                + "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")))

        XCTAssertEqual(request.path, "/ulanzi/button/abc")
        XCTAssertEqual(request.body, data(body))
    }

    /// A body not all there yet is no request yet: more bytes may come.
    func testATruncatedBodyIsNotARequestYet() {
        let truncated = data("POST /claude-code/abc HTTP/1.1\r\nContent-Length: 20\r\n\r\n{\"a\":1")

        XCTAssertNil(HubRequest.parse(truncated))
        XCTAssertEqual(HubRequest.read(truncated), .incomplete)
    }

    /// Headers without their blank line are not finished either.
    func testUnfinishedHeadersAreIncomplete() {
        XCTAssertEqual(HubRequest.read(data("POST /claude-code/abc HTTP/1.1\r\nContent-Le")), .incomplete)
        XCTAssertEqual(HubRequest.read(Data()), .incomplete)
    }

    /// No `Content-Length`: no body, and the request is whole at the blank
    /// line.
    func testARequestWithoutABodyHasAnEmptyOne() throws {
        let request = try XCTUnwrap(HubRequest.parse(data("GET /claude-code/abc HTTP/1.1\r\nHost: x\r\n\r\n")))

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.body, Data())
    }

    /// Header names are read in any case, with or without the space.
    func testHeaderNamesAreReadInAnyCase() {
        for header in ["content-length: 2", "CONTENT-LENGTH: 2", "Content-length:2", "Content-Length:  2 "] {
            let request = HubRequest.parse(data("POST /x HTTP/1.1\r\n\(header)\r\n\r\n{}"))
            XCTAssertEqual(request?.body, data("{}"), header)
        }
    }

    /// Bytes past the declared body are not part of it.
    func testBytesPastTheBodyAreLeftOut() {
        XCTAssertEqual(HubRequest.parse(data("POST /x HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}{}"))?.body, data("{}"))
    }

    /// A query is not part of the path.
    func testTheQueryIsNotPartOfThePath() {
        XCTAssertEqual(HubRequest.parse(data("POST /claude-code/abc?x=1 HTTP/1.1\r\n\r\n"))?.path, "/claude-code/abc")
    }

    /// What isn't an HTTP/1 request is malformed, whatever comes next: the
    /// server answers it at once rather than waiting for more.
    func testWhatIsNotHTTPIsMalformed() {
        for text in ["hello\r\n\r\n",
                     "POST /x\r\n\r\n",
                     "POST x HTTP/1.1\r\n\r\n",
                     "POST /x SPDY/3\r\n\r\n",
                     "POST /x HTTP/1.1\r\nno colon here\r\n\r\n",
                     "POST /x HTTP/1.1\r\nContent-Length: two\r\n\r\n",
                     "POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n"] {
            XCTAssertEqual(HubRequest.read(data(text)), .malformed, text)
        }
    }
}
