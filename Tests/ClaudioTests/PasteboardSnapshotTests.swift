import AppKit
import XCTest
@testable import Claudio

@MainActor
final class PasteboardSnapshotTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: .init("claudio-tests-\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    func testRestoresTheClipboardAfterThePaste() {
        pasteboard.setText("before")
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let pasted = pasteboard.setText("pasted")

        XCTAssertTrue(snapshot.restore(to: pasteboard, ifUnchangedSince: pasted))
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testLeavesACopyMadeDuringThePaste() {
        pasteboard.setText("before")
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let pasted = pasteboard.setText("pasted")
        pasteboard.setText("copied meanwhile")

        XCTAssertFalse(snapshot.restore(to: pasteboard, ifUnchangedSince: pasted))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
    }
}
