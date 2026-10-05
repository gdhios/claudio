import XCTest
@testable import Claudio

/// The face Claudio installs on the clock. Two contracts hold it to the rest
/// of the app: the gazes its config accepts are the ones the bridge sends,
/// and its bytes are the ones the device hands back, so that a face already
/// there is never sent again.
final class UlanziFaceScriptTests: XCTestCase {

    /// The device keeps the source to the byte, and Claudio compares it to
    /// the byte: one newline at the end, not one more.
    func testTheSourceEndsOnASingleNewline() {
        XCTAssertTrue(UlanziFaceScript.source.hasSuffix("\nreturn Claudio()\n"))
        XCTAssertFalse(UlanziFaceScript.source.hasSuffix("\n\n"))
        XCTAssertTrue(UlanziFaceScript.source.hasPrefix("# @name    Claudio\n"))
    }

    /// The app the script declares is the one every path names.
    func testTheScriptIsTheAppItsPathsName() {
        XCTAssertEqual(UlanziFaceScript.appName, "Claudio")
    }

    /// Every gaze the bridge can send is in the script's list, and nothing
    /// else is: a gaze missing there is refused by the device with a 422.
    func testTheScriptAcceptsEveryGazeTheBridgeSends() throws {
        let options = try XCTUnwrap(Self.gazeOptions)
        let sent = Set(ClaudioMascot.Gaze.allCases.map(\.rawValue) + [UlanziBridge.off])
        XCTAssertEqual(Set(options), sent)
    }

    /// Installed and not yet told anything, the face stays hidden: a clock
    /// that shows Claudio before he works would be lying.
    func testAFreshInstallShowsNothing() throws {
        let line = try XCTUnwrap(Self.gazeLine)
        XCTAssertTrue(line.contains("default=off"), line)
    }

    // MARK: - Reading the script's config

    private static var gazeLine: String? {
        UlanziFaceScript.source.split(separator: "\n")
            .first { $0.hasPrefix("# @config  gaze") }
            .map(String.init)
    }

    private static var gazeOptions: [String]? {
        guard let line = gazeLine,
              let match = line.firstMatch(of: /options=([a-z,]+)/) else { return nil }
        return match.1.split(separator: ",").map(String.init)
    }
}
