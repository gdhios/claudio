import XCTest
@testable import Claudio

/// The relay hooked into Claude Code by Claudio itself. In
/// `~/.claude/settings.json`, four entries go in, one per event, and only
/// ever those: every other hook, every other setting, stays as it was. Out
/// go exactly the entries that run the relay, wherever it lives. The pure
/// half is tested on dictionaries; the files only ever in a temporary
/// folder, never this Mac's settings.
final class ClaudeCodeHookInstallerTests: XCTestCase {

    private var folder: URL!
    private let command = "python3 '/Users/g/Library/Application Support/Claudio/claudio-claude-code.py'"
    private let matcher = "permission_prompt|idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog"

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.hookInstaller.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Helpers

    private func object(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            XCTFail("not a JSON object: \(json)", file: file, line: line)
            return [:]
        }
        return object
    }

    /// The same JSON whatever its spacing and key order, to compare.
    private func text(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }

    private func assertSame(_ actual: [String: Any], _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(text(actual), text(object(expected)), file: file, line: line)
    }

    private func handler(_ command: String) -> String {
        #"{"type":"command","command":"\#(command)","timeout":10,"async":true}"#
    }

    /// The four groups the relay gets, after whatever was there.
    private var relayGroups: (stop: String, notification: String, prompt: String, end: String) {
        let one = #"{"hooks":[\#(handler(command))]}"#
        return (one, #"{"matcher":"\#(matcher)","hooks":[\#(handler(command))]}"#, one, one)
    }

    // MARK: - Installing, on the dictionary

    /// Nothing there: the four events, each with its group, the
    /// notifications that wait for Guillaume only.
    func testInstallingIntoNothingAddsTheFourEntries() {
        let groups = relayGroups
        assertSame(ClaudeCodeHookInstaller.install(into: [:], command: command), """
        {"hooks":{"Stop":[\(groups.stop)],"Notification":[\(groups.notification)],
                  "UserPromptSubmit":[\(groups.prompt)],"SessionEnd":[\(groups.end)]}}
        """)
    }

    /// Every other setting, every other event and every other group of the
    /// same events stays as it was, where it was; the relay's groups come
    /// after them.
    func testInstallingKeepsEverythingElse() {
        let settings = object("""
        {"model":"opus","env":{"A":"1"},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard.sh"}]}],
                  "Stop":[{"hooks":[{"type":"command","command":"python3 'island.py'"}]}]}}
        """)
        let groups = relayGroups

        assertSame(ClaudeCodeHookInstaller.install(into: settings, command: command), """
        {"model":"opus","env":{"A":"1"},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard.sh"}]}],
                  "Stop":[{"hooks":[{"type":"command","command":"python3 'island.py'"}]},\(groups.stop)],
                  "Notification":[\(groups.notification)],
                  "UserPromptSubmit":[\(groups.prompt)],"SessionEnd":[\(groups.end)]}}
        """)
    }

    /// Installed twice is installed once.
    func testInstallingTwiceDoublesNothing() {
        let once = ClaudeCodeHookInstaller.install(into: [:], command: command)

        XCTAssertEqual(text(ClaudeCodeHookInstaller.install(into: once, command: command)), text(once))
    }

    /// The relay already hooked from elsewhere, the repository for one:
    /// those entries go, and the new ones take their place.
    func testInstallingReplacesTheRelayHookedFromElsewhere() {
        let old = "python3 '/Users/g/Documents/claude/CLAUDIO/Hooks/claudio-claude-code.py'"
        let settings = object("""
        {"hooks":{"Stop":[{"hooks":[\(handler(old))]},{"hooks":[{"type":"command","command":"cc-status"}]}],
                  "Notification":[{"matcher":"\(matcher)","hooks":[\(handler(old))]}]}}
        """)
        let groups = relayGroups

        assertSame(ClaudeCodeHookInstaller.install(into: settings, command: command), """
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"cc-status"}]},\(groups.stop)],
                  "Notification":[\(groups.notification)],
                  "UserPromptSubmit":[\(groups.prompt)],"SessionEnd":[\(groups.end)]}}
        """)
    }

    // MARK: - Removing, on the dictionary

    /// Out go the relay's entries alone: in a group with another hook, the
    /// other stays; a group left empty goes, and so does an event left
    /// with none.
    func testRemovingTakesTheRelayAlone() {
        let settings = object("""
        {"theme":"dark",
         "hooks":{"Stop":[{"hooks":[{"type":"command","command":"cc-status"},\(handler(command))]}],
                  "Notification":[{"matcher":"*","hooks":[{"type":"command","command":"island.py"}]},
                                  {"matcher":"\(matcher)","hooks":[\(handler(command))]}],
                  "SessionEnd":[{"hooks":[\(handler(command))]}]}}
        """)

        assertSame(ClaudeCodeHookInstaller.remove(from: settings), """
        {"theme":"dark",
         "hooks":{"Stop":[{"hooks":[{"type":"command","command":"cc-status"}]}],
                  "Notification":[{"matcher":"*","hooks":[{"type":"command","command":"island.py"}]}]}}
        """)
    }

    /// Installed then removed: back to what was there, nothing left behind.
    func testRemovingWhatWasInstalledLeavesWhatWasThere() {
        let settings = object(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"cc-status"}]}]}}"#)

        let removed = ClaudeCodeHookInstaller.remove(from: ClaudeCodeHookInstaller.install(into: settings, command: command))

        XCTAssertEqual(text(removed), text(settings))
        XCTAssertEqual(text(ClaudeCodeHookInstaller.remove(from: [:])), "{}")
    }

    /// What it didn't empty, it leaves: an empty event, or empty hooks,
    /// that were there before stay there.
    func testRemovingLeavesWhatWasAlreadyEmpty() {
        for json in [#"{"hooks":{}}"#, #"{"hooks":{"Stop":[]}}"#, #"{"hooks":{"Stop":[{"hooks":[]}]}}"#] {
            XCTAssertEqual(text(ClaudeCodeHookInstaller.remove(from: object(json))), text(object(json)), json)
        }
    }

    // MARK: - Installed or not

    /// Installed is a Stop entry running the relay, wherever it lives.
    func testInstalledMeansAStopEntryRunningTheRelay() {
        XCTAssertFalse(ClaudeCodeHookInstaller.isInstalled([:]))
        XCTAssertTrue(ClaudeCodeHookInstaller.isInstalled(ClaudeCodeHookInstaller.install(into: [:], command: command)))
        XCTAssertTrue(ClaudeCodeHookInstaller.isInstalled(object("""
        {"hooks":{"Stop":[{"hooks":[\(handler("python3 '/elsewhere/claudio-claude-code.py'"))]}]}}
        """)))
        XCTAssertFalse(ClaudeCodeHookInstaller.isInstalled(object("""
        {"hooks":{"Notification":[{"hooks":[\(handler(command))]}],
                  "Stop":[{"hooks":[{"type":"command","command":"cc-status"}]}]}}
        """)))
    }

    /// The relay's path in single quotes, as a shell reads it, a quote in
    /// it included.
    func testTheCommandQuotesThePath() {
        XCTAssertEqual(ClaudeCodeHookInstaller.command(for: URL(fileURLWithPath: "/Users/g/Library/Application Support/Claudio/claudio-claude-code.py")),
                       command)
        XCTAssertEqual(ClaudeCodeHookInstaller.command(for: URL(fileURLWithPath: "/Users/o'neil/r.py")),
                       #"python3 '/Users/o'\''neil/r.py'"#)
    }

    // MARK: - The files

    private var settingsURL: URL { folder.appendingPathComponent(".claude/settings.json") }
    private var backupURL: URL { folder.appendingPathComponent(".claude/settings.json.claudio-backup") }
    private var relaySource: URL { folder.appendingPathComponent("Claudio.app/Contents/Resources/claudio-claude-code.py") }
    private var relayDestination: URL { folder.appendingPathComponent("Application Support/Claudio/claudio-claude-code.py") }
    private let relayScript = "#!/usr/bin/env python3\nprint('relay')\n"

    private func installer(relay: Bool = true) throws -> ClaudeCodeHookInstaller {
        if relay {
            try FileManager.default.createDirectory(at: relaySource.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(relayScript.utf8).write(to: relaySource)
        }
        return ClaudeCodeHookInstaller(settingsURL: settingsURL, relaySource: relay ? relaySource : nil,
                                       relayDestination: relayDestination)
    }

    private func writeSettings(_ text: String) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settingsURL)
    }

    private func readSettings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
    }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    /// Installing: the settings kept aside first, the relay copied where it
    /// stays put, runnable, and the entries pointing at that copy.
    func testInstallingBacksUpCopiesTheRelayAndHooksIt() throws {
        let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"cc-status"}]}]}}"#
        try writeSettings(original)
        let installer = try installer()
        XCTAssertEqual(installer.state(), .absent)

        try installer.install()

        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), original)
        XCTAssertEqual(try String(contentsOf: relayDestination, encoding: .utf8), relayScript)
        XCTAssertEqual(try permissions(relayDestination), 0o755)
        let expected = ClaudeCodeHookInstaller.install(into: object(original),
                                                      command: ClaudeCodeHookInstaller.command(for: relayDestination))
        XCTAssertEqual(text(try readSettings()), text(expected))
        XCTAssertEqual(installer.state(), .installed)
    }

    /// Written the way a person reads it: indented, keys sorted, slashes
    /// as they are, and with the permissions the file had.
    func testTheSettingsAreWrittenReadably() throws {
        try writeSettings(#"{"b":1,"a":"x/y"}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)

        try installer().install()

        let written = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(written.hasPrefix("{\n  \"a\" : \"x/y\",\n  \"b\" : 1,\n"), written)
        XCTAssertEqual(try permissions(settingsURL), 0o600)
    }

    /// No settings yet: the file is made, and there was nothing to keep.
    func testInstallingWithoutSettingsMakesThem() throws {
        let installer = try installer()

        try installer.install()

        XCTAssertTrue(ClaudeCodeHookInstaller.isInstalled(try readSettings()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    /// The relay copied again over an older one, made runnable again.
    func testInstallingAgainReplacesTheRelay() throws {
        try FileManager.default.createDirectory(at: relayDestination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("old".utf8).write(to: relayDestination)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: relayDestination.path)

        try installer().install()

        XCTAssertEqual(try String(contentsOf: relayDestination, encoding: .utf8), relayScript)
        XCTAssertEqual(try permissions(relayDestination), 0o755)
    }

    /// Settings that are no JSON are never written: neither installing nor
    /// removing touches them, the relay is not copied, and the state says
    /// why.
    func testUnreadableSettingsAreNeverWritten() throws {
        let broken = #"{"hooks": {"Stop": ["#
        try writeSettings(broken)
        let installer = try installer()

        XCTAssertThrowsError(try installer.install())
        XCTAssertThrowsError(try installer.remove())

        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: relayDestination.path))
        guard case .unreadable(let reason) = installer.state() else {
            return XCTFail("state \(installer.state())")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    /// Settings shaped in a way Claude Code itself wouldn't read, hooks
    /// that are no object, are left alone too.
    func testSettingsOfAnotherShapeAreLeftAlone() throws {
        for shape in [#"[1, 2]"#, #"{"hooks":["Stop"]}"#, #"{"hooks":{"Stop":{"command":"x"}}}"#] {
            try writeSettings(shape)
            let installer = try installer()

            XCTAssertThrowsError(try installer.install(), shape)
            XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), shape)
            guard case .unreadable = installer.state() else { return XCTFail("\(shape): \(installer.state())") }
        }
    }

    /// Removing: kept aside first, then the relay's entries out; the relay
    /// itself stays where it was copied.
    func testRemovingBacksUpAndTakesTheEntriesOut() throws {
        let installer = try installer()
        try writeSettings(#"{"model":"opus"}"#)
        try installer.install()
        let installed = try String(contentsOf: settingsURL, encoding: .utf8)

        try installer.remove()

        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), installed)
        XCTAssertEqual(text(try readSettings()), #"{"model":"opus"}"#)
        XCTAssertTrue(FileManager.default.fileExists(atPath: relayDestination.path))
        XCTAssertEqual(installer.state(), .absent)
    }

    /// Nothing to remove: nothing is written, not even a backup.
    func testRemovingNothingWritesNothing() throws {
        let original = #"{"model": "opus"}"#
        try writeSettings(original)

        try installer().remove()

        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    /// No settings at all, nothing to remove: no file is made.
    func testRemovingWithoutSettingsMakesNoFile() throws {
        let installer = try installer()

        try installer.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(installer.state(), .absent)
    }

    /// A version built without the relay can't install it, and says so,
    /// but one hooked already still reads as installed, and can be removed.
    func testWithoutTheRelayNothingIsInstalled() throws {
        try writeSettings(#"{"model":"opus"}"#)
        let bare = try installer(relay: false)

        XCTAssertEqual(bare.state(), .noRelay)
        XCTAssertThrowsError(try bare.install()) { error in
            XCTAssertEqual(error as? ClaudeCodeHookInstaller.Failure, .noRelay)
        }
        XCTAssertEqual(text(try readSettings()), #"{"model":"opus"}"#)

        try installer().install()
        XCTAssertEqual(bare.state(), .installed)
        try bare.remove()
        XCTAssertEqual(bare.state(), .noRelay)
    }
}
