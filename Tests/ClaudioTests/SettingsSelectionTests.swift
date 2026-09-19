import XCTest
@testable import Claudio

/// Which tab Settings shows. It used to be state locked inside the view, set
/// once when the window was built: asking for a tab afterwards changed
/// nothing, and a `claudio://` link — or the plugin sending someone to its
/// own switch — brought the window forward on whatever tab was already
/// there. The tab is now a value the window controller writes and the view
/// observes, and that is what these tests hold.
@MainActor
final class SettingsSelectionTests: XCTestCase {

    /// Where Settings opens when nobody asked for anything.
    func testSettingsStartsOnTheGeneralTab() {
        XCTAssertEqual(SettingsSelection().section, .general)
    }

    /// The case the whole change exists for: a second request, with the
    /// window long since built, moves the tab.
    func testAskingForATabAgainMovesIt() {
        let selection = SettingsSelection()
        selection.section = .dictation
        XCTAssertEqual(selection.section, .dictation)

        selection.section = .streamDeck
        XCTAssertEqual(selection.section, .streamDeck)
    }

    /// The sidebar keeps its say: clicking a row is what moves the tab the
    /// rest of the time.
    func testTheSidebarMovesTheTabToo() {
        let selection = SettingsSelection()
        selection.sidebar.wrappedValue = .prompts
        XCTAssertEqual(selection.section, .prompts)
        XCTAssertEqual(selection.sidebar.wrappedValue, .prompts)
    }

    /// A sidebar can end up with nothing selected — a ⌘-click on the row
    /// that was selected. The tab stays where it was rather than the window
    /// emptying itself.
    func testDeselectingInTheSidebarLeavesTheTabAlone() {
        let selection = SettingsSelection()
        selection.section = .streamDeck
        selection.sidebar.wrappedValue = nil
        XCTAssertEqual(selection.section, .streamDeck)
    }
}
