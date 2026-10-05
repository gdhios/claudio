import XCTest
@testable import Claudio

/// The board's file: what it writes, it reads back, and anything else,
/// missing or unreadable, is no board at all. In a temporary folder.
final class ClaudeCodeBoardFileTests: XCTestCase {

    private var folder: URL!
    private var file: ClaudeCodeBoardFile!

    private let snapshot = ClaudeCodeBoard.Snapshot(
        held: [ClaudeCodeBoard.Snapshot.Held(name: "cc-5f0c2a9e", sessionID: "5f0c2a9e-aaaa-4bbb-8ccc-000000000001",
                                             order: 3)],
        waits: [ClaudeCodeBoard.Snapshot.Waiting(sessionID: "5f0c2a9e-aaaa-4bbb-8ccc-000000000001", level: .red,
                                                 since: Date(timeIntervalSince1970: 1_800_000_000.25))])

    override func setUp() {
        super.setUp()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.board.\(UUID().uuidString)")
        file = ClaudeCodeBoardFile(directory: folder.appendingPathComponent("Claudio"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// Written in a folder made for it, next to the handshake files, and
    /// read back as it was.
    func testWhatIsWrittenIsReadBack() throws {
        try file.save(snapshot)

        XCTAssertEqual(file.load(), snapshot)
        XCTAssertEqual(file.url.lastPathComponent, "claude-code-board.json")
        XCTAssertEqual(ClaudeCodeBoardFile().directory, BridgeHandshakeFile.defaultDirectory)
    }

    /// Written again, it holds the last board only.
    func testTheLastBoardWrittenIsTheOneRead() throws {
        try file.save(snapshot)
        try file.save(ClaudeCodeBoard.Snapshot())

        XCTAssertEqual(file.load(), ClaudeCodeBoard.Snapshot())
    }

    /// No file yet: no board.
    func testNoFileIsNoBoard() {
        XCTAssertNil(file.load())
    }

    /// Cut short, not JSON, not the board's, or of another version: no
    /// board, rather than a wrong one.
    func testAnUnreadableFileIsNoBoard() throws {
        try FileManager.default.createDirectory(at: file.directory, withIntermediateDirectories: true)
        for contents in ["", "{not json", "[]", "{}", #"{"v":2,"held":[],"waits":[]}"#,
                         #"{"v":1,"held":[{"name":"cc-1"}],"waits":[]}"#,
                         #"{"v":1,"held":[],"waits":[{"sessionID":"s","level":"pink","since":0}]}"#] {
            try Data(contents.utf8).write(to: file.url)
            XCTAssertNil(file.load(), contents)
        }
    }
}
