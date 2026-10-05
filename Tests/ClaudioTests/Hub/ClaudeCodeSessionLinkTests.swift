import XCTest
@testable import Claudio

/// The way back from a hook's session to its conversation in the Claude app.
/// The hook names the session by the engine's id; the app opens it by its
/// own; the file of the live process in `~/.claude/sessions` holds both.
/// Read from a temporary folder, never this Mac's own.
final class ClaudeCodeSessionLinkTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.sessions.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private func write(_ name: String, _ json: String) throws {
        try Data(json.utf8).write(to: directory.appendingPathComponent(name))
    }

    /// A session file as Claude Code writes it, `updatedAt` in milliseconds
    /// since 1970, as an integer.
    private func session(_ engine: String, app: String?, updatedAt: String = "1791206181815",
                         entrypoint: String = "claude-desktop") -> String {
        let host = app.map { #","hostSessionId":"\#($0)""# } ?? ""
        return #"{"pid":4242,"sessionId":"\#(engine)"\#(host),"entrypoint":"\#(entrypoint)","updatedAt":\#(updatedAt)}"#
    }

    private func link(_ id: String) -> URL? {
        ClaudeCodeSessionLink.url(forSession: id, in: directory)
    }

    /// The file whose engine id is the hook's gives the app's link; the
    /// other session's file is left alone.
    func testTheMatchingFileGivesTheAppsLink() throws {
        try write("4242.json", session("engine-a", app: "local_aaa"))
        try write("4343.json", session("engine-b", app: "local_bbb"))

        XCTAssertEqual(link("engine-a"), URL(string: "claude://claude.ai/epitaxy/local_aaa"))
    }

    /// Two files for one session, a process restarted for instance: the one
    /// written last wins, whatever the folder's order.
    func testTheMostRecentOfTwoMatchesWins() throws {
        try write("5000.json", session("engine-a", app: "local_new", updatedAt: "1791206186815"))
        try write("4000.json", session("engine-a", app: "local_old", updatedAt: "1791206181815"))

        XCTAssertEqual(link("engine-a"), URL(string: "claude://claude.ai/epitaxy/local_new"))
    }

    /// Milliseconds are read as milliseconds: against a file dated in
    /// seconds an hour later, the later one still wins.
    func testUpdatedAtIsReadInMilliseconds() throws {
        try write("1.json", session("engine-a", app: "local_ms", updatedAt: "1791206181815"))
        try write("2.json", session("engine-a", app: "local_s", updatedAt: "1791209781"))

        XCTAssertEqual(link("engine-a"), URL(string: "claude://claude.ai/epitaxy/local_s"))
    }

    /// A date written as text is compared as a date.
    func testADateWrittenAsTextIsComparedToo() throws {
        try write("1.json", session("engine-a", app: "local_late", updatedAt: #""2026-10-05T11:00:00.000Z""#))
        try write("2.json", session("engine-a", app: "local_early", updatedAt: #""2026-10-05T10:00:00Z""#))

        XCTAssertEqual(link("engine-a"), URL(string: "claude://claude.ai/epitaxy/local_late"))
    }

    /// No app id, or an empty one, opens nothing: a session in a terminal
    /// has none. The entry point is not asked for: an app id is enough.
    func testOnlyAnAppIDMakesALink() throws {
        try write("1.json", session("engine-a", app: nil))
        try write("2.json", session("engine-b", app: ""))
        try write("3.json", session("engine-c", app: "local_ccc", entrypoint: "cli"))

        XCTAssertNil(link("engine-a"))
        XCTAssertNil(link("engine-b"))
        XCTAssertEqual(link("engine-c"), URL(string: "claude://claude.ai/epitaxy/local_ccc"))
    }

    /// A file that can't be read as a session is passed over, and so is
    /// anything that isn't a `.json`.
    func testWhatIsNotASessionFileIsIgnored() throws {
        try write("broken.json", "{not json")
        try write("list.json", "[]")
        try write("notes.txt", session("engine-a", app: "local_txt"))
        try write("4242.json", session("engine-a", app: "local_aaa"))

        XCTAssertEqual(link("engine-a"), URL(string: "claude://claude.ai/epitaxy/local_aaa"))
    }

    /// No file for the session, or no folder at all: no link.
    func testNoMatchIsNoLink() throws {
        try write("4242.json", session("engine-a", app: "local_aaa"))

        XCTAssertNil(link("engine-z"))
        XCTAssertNil(ClaudeCodeSessionLink.url(forSession: "engine-a",
                                               in: directory.appendingPathComponent("missing")))
    }

    /// An app id that a link can't carry as it is gets escaped, not dropped.
    func testAnAppIDIsEscapedInTheLink() throws {
        try write("1.json", session("engine-a", app: "local a/b"))

        XCTAssertEqual(link("engine-a")?.absoluteString, "claude://claude.ai/epitaxy/local%20a%2Fb")
    }

    /// Claude Code's own folder, in the home folder.
    func testTheDefaultFolderIsClaudeCodesSessions() {
        XCTAssertTrue(ClaudeCodeSessionLink.defaultDirectory.path.hasSuffix("/.claude/sessions"),
                      ClaudeCodeSessionLink.defaultDirectory.path)
    }
}
