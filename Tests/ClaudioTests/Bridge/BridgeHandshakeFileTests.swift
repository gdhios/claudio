import XCTest
@testable import Claudio

/// The one thing the plugin is told out of band: where to knock and with
/// what. Its shape is a contract — the plugin reads these four keys — and
/// its permissions are the whole of the bridge's security, since anyone who
/// reads the token can drive Claudio.
///
/// Written to a temporary folder: never this Mac's own handshake file, which
/// a running Claudio owns.
final class BridgeHandshakeFileTests: XCTestCase {

    private var directory: URL!
    private var file: BridgeHandshakeFile!

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.handshake.\(UUID().uuidString)")
        file = BridgeHandshakeFile(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        file = nil
        super.tearDown()
    }

    private func writtenObject() throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url))
        return try XCTUnwrap(parsed as? [String: Any], "the handshake file is not a JSON object")
    }

    /// The name is part of the contract: the plugin looks this file up by
    /// path, with no way to ask.
    func testItSitsUnderItsOwnName() {
        XCTAssertEqual(file.url, directory.appendingPathComponent("streamdeck-bridge.json"))
    }

    /// Claudio's own folder, which may not exist yet on a fresh install.
    func testTheDefaultIsClaudiosApplicationSupportFolder() {
        XCTAssertTrue(
            BridgeHandshakeFile().url.path
                .hasSuffix("/Library/Application Support/Claudio/streamdeck-bridge.json"),
            BridgeHandshakeFile().url.path)
    }

    // MARK: - Writing

    /// The four keys, with the values handed in: a plugin reading anything
    /// else knocks on the wrong port, or with the wrong token.
    func testItWritesTheFourKeysItWasGiven() throws {
        try file.write(port: 51234, token: "abc123", pid: 4242)

        let object = try writtenObject()
        XCTAssertEqual(object["v"] as? Int, BridgeProtocol.version)
        XCTAssertEqual(object["port"] as? Int, 51234)
        XCTAssertEqual(object["token"] as? String, "abc123")
        XCTAssertEqual(object["pid"] as? Int, 4242)
        XCTAssertEqual(Set(object.keys), ["v", "port", "token", "pid"])
    }

    /// The folder is made on the way: a Mac that never ran Claudio has none.
    func testItCreatesTheFolderItNeeds() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try file.write(port: 1, token: "t", pid: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }

    /// Readable by its owner alone. The token in it is what drives Claudio:
    /// another account on this Mac must not be able to read it.
    func testItIsReadableByItsOwnerAlone() throws {
        try file.write(port: 1, token: "t", pid: 2)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    /// A second start writes over the first: a stale port and a stale token
    /// would send the plugin knocking on nothing.
    func testWritingAgainReplacesWhatWasThere() throws {
        try file.write(port: 1, token: "old", pid: 2)
        try file.write(port: 51235, token: "new", pid: 3)

        let object = try writtenObject()
        XCTAssertEqual(object["token"] as? String, "new")
        XCTAssertEqual(object["port"] as? Int, 51235)
    }

    // MARK: - Removing

    /// The bridge stopping takes its file with it: a handshake file outliving
    /// the socket is an invitation to a port nobody answers.
    func testRemovingDeletesTheFile() throws {
        try file.write(port: 1, token: "t", pid: 2)
        file.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    /// Stopping a bridge that never started, or quitting twice: nothing to
    /// remove is not a failure.
    func testRemovingWhatIsNotThereDoesNothing() {
        file.remove()
        file.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    // MARK: - The token

    /// 32 random bytes in hex: long enough that guessing it is out of the
    /// question, and lowercase so both sides compare the same string.
    func testTheTokenIsSixtyFourLowercaseHexCharacters() {
        let token = BridgeHandshakeFile.makeToken()
        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy { $0.isHexDigit && !$0.isUppercase }, token)
    }

    /// A token reused from one launch to the next would outlive the socket
    /// it protects.
    func testTwoTokensDiffer() {
        XCTAssertNotEqual(BridgeHandshakeFile.makeToken(), BridgeHandshakeFile.makeToken())
    }
}
