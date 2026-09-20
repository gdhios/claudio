import XCTest
@testable import Claudio

/// The door. A connection says `hello` with the token from the handshake
/// file, or it is turned away — and that decision is a pure function, so it
/// is proved here without opening a socket.
///
/// Every frame is built from the shared fixture: a field renamed on the
/// plugin's side breaks this, which is the point.
final class BridgeHelloTests: XCTestCase {

    /// The token the fixture's `hello` carries, which is the one the server
    /// is given in these tests.
    private var token: String {
        get throws { try XCTUnwrap(BridgeFixtures.object("hello")["token"] as? String) }
    }

    /// The fixture's frame, with some of its fields replaced.
    private func frame(_ name: String, changing: [String: Any] = [:]) throws -> Data {
        var object = try BridgeFixtures.object(name)
        for (key, value) in changing { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func assertAdmitted(_ frame: Data, token: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let code) = BridgeServer.admit(firstFrame: frame, token: token) {
            XCTFail("turned away with “\(code.rawValue)”", file: file, line: line)
        }
    }

    private func assertRefused(_ frame: Data, token: String, with expected: BridgeErrorCode,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch BridgeServer.admit(firstFrame: frame, token: token) {
        case .success:
            XCTFail("let in", file: file, line: line)
        case .failure(let code):
            XCTAssertEqual(code, expected, file: file, line: line)
        }
    }

    // MARK: - The plugin as it should be

    func testTheFixturesHelloIsLetIn() throws {
        assertAdmitted(try BridgeFixtures.data("hello"), token: try token)
    }

    // MARK: - The token

    /// The whole point of the token: a connection that didn't read the 0600
    /// file cannot drive Claudio.
    func testAWrongTokenIsTurnedAway() throws {
        assertRefused(try frame("hello", changing: ["token": "not the token"]),
                      token: try token, with: .token)
    }

    /// Compared as it is written: a token differing only in case is another
    /// token, and the handshake file only ever holds lowercase hex.
    func testTheTokenIsComparedExactly() throws {
        assertRefused(try frame("hello", changing: ["token": try token.uppercased()]),
                      token: try token, with: .token)
    }

    /// Nothing is read from a frame that is not a `hello`: a plugin that
    /// opens by pressing a key gets the same answer as a stranger.
    func testACommandBeforeTheHandshakeIsTurnedAway() throws {
        assertRefused(try BridgeFixtures.data("action-correct"), token: try token, with: .token)
        assertRefused(try BridgeFixtures.data("dictation-down"), token: try token, with: .token)
    }

    /// Anything that isn't a frame at all. Refused as a stranger rather than
    /// as an old version: there is nothing in it to tell the two apart.
    func testGarbageIsTurnedAway() throws {
        for junk in ["", "{", "[]", "hello", "{\"type\":\"hello\"}"] {
            assertRefused(Data(junk.utf8), token: try token, with: .token)
        }
    }

    // MARK: - The version

    /// A plugin speaking another protocol is told so, rather than being left
    /// to guess at a token that was right all along.
    func testAnotherProtocolVersionIsNamedAsSuch() throws {
        assertRefused(try frame("hello", changing: ["v": BridgeProtocol.version + 1]),
                      token: try token, with: .version)
        assertRefused(try frame("hello", changing: ["v": 0]), token: try token, with: .version)
    }

    /// The version is read first: an old plugin with an old token has two
    /// things wrong, and the one worth reporting is the protocol.
    func testTheVersionIsCheckedBeforeTheToken() throws {
        assertRefused(try frame("hello", changing: ["v": 2, "token": "not the token"]),
                      token: try token, with: .version)
    }

    // MARK: - What goes back

    /// The refusal the plugin reads in its log, frame for frame.
    func testTheRefusalIsTheFixturesFrame() throws {
        try BridgeFixtures.assertEncoding(BridgeServer.refusal(.version),
                                          matches: "error-version")
    }

    /// Both refusals say which one they are: the code is what the plugin
    /// switches on, the sentence is only there to be read.
    func testBothRefusalsCarryTheirOwnCode() {
        for code in [BridgeErrorCode.version, .token] {
            guard case .error(let sent, let message) = BridgeServer.refusal(code) else {
                return XCTFail("\(code.rawValue) is no error frame")
            }
            XCTAssertEqual(sent, code)
            XCTAssertFalse(message.isEmpty)
        }
    }
}
