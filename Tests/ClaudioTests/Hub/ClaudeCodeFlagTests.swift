import XCTest
@testable import Claudio

/// The square a Claude Code turn opens with, read the way the Python hook
/// before Claudio read it: anywhere in the message, and in a fixed order
/// when there are several, not in the order they appear.
final class ClaudeCodeFlagTests: XCTestCase {

    /// Each square is its flag, with its word and its colour.
    func testEachSquareIsItsFlag() {
        XCTAssertEqual(ClaudeCodeFlag.in("🟩 FINI — c'est livré"), .done)
        XCTAssertEqual(ClaudeCodeFlag.in("---\n\n🟧 **DÉCISION — laquelle ?**"), .decision)
        XCTAssertEqual(ClaudeCodeFlag.in("🟥 BLOCAGE"), .blocked)
        XCTAssertEqual(ClaudeCodeFlag.in("🟦 INFO"), .info)

        XCTAssertEqual(ClaudeCodeFlag.allCases.map(\.word), ["FINI", "DÉCISION", "BLOCAGE", "INFO"])
        XCTAssertEqual(ClaudeCodeFlag.allCases.map(\.color), ["#2ECC40", "#FF851B", "#FF2D2D", "#3D9BFF"])
    }

    /// Several squares: green, then orange, then red, then blue, whatever
    /// comes first in the text.
    func testTheSearchOrderDecidesBetweenSeveralSquares() {
        XCTAssertEqual(ClaudeCodeFlag.in("🟦 INFO, puis 🟩"), .done)
        XCTAssertEqual(ClaudeCodeFlag.in("🟥 🟧"), .decision)
        XCTAssertEqual(ClaudeCodeFlag.in("🟦 et 🟥"), .blocked)
    }

    /// A square followed by a variation selector is still that square.
    func testASquareWithAVariationSelectorStillCounts() {
        XCTAssertEqual(ClaudeCodeFlag.in("🟧\u{FE0F} DÉCISION"), .decision)
    }

    /// A short answer without a flag, or no message at all: no flag.
    func testNoSquareIsNoFlag() {
        XCTAssertNil(ClaudeCodeFlag.in("Oui, c'est fait."))
        XCTAssertNil(ClaudeCodeFlag.in("⬛️ 🟨 🟪"))
        XCTAssertNil(ClaudeCodeFlag.in(""))
        XCTAssertNil(ClaudeCodeFlag.in(nil))
    }
}
