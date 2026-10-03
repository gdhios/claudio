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

    /// Settings brought up on a named tab: the tab moves, and the panes that
    /// read this Mac are told to look again. The Stream Deck tab is the one
    /// that needs it — the plugin may have been installed in the meantime,
    /// and a window that never closed would keep saying "plugin absent".
    func testBringingSettingsUpOnATabMovesItAndAsksForAFreshLook() {
        let selection = SettingsSelection()
        var looks = 0
        selection.onShown = { looks += 1 }

        selection.broughtUp(on: .streamDeck, alreadyOnScreen: false)
        XCTAssertEqual(selection.section, .streamDeck)
        XCTAssertEqual(looks, 1)

        selection.broughtUp(on: .streamDeck, alreadyOnScreen: true)
        XCTAssertEqual(looks, 2)
    }

    /// Brought up with nothing named — the menu's own entry: the tab stays
    /// where it was, and the fresh look is asked for all the same.
    func testBringingSettingsUpWithNoTabNamedLeavesItWhereItWas() {
        let selection = SettingsSelection()
        selection.section = .dictation
        var looks = 0
        selection.onShown = { looks += 1 }

        selection.broughtUp(on: nil, alreadyOnScreen: true)
        XCTAssertEqual(selection.section, .dictation)
        XCTAssertEqual(looks, 1)
    }

    /// The window is reused from one opening to the next, and SwiftUI
    /// replays no `.onAppear` or `.task` in a view that never left it: the
    /// dictation history and the Claude model list stayed as the first
    /// opening found them. Each opening is counted, for the view to rebuild
    /// its pane on; a window brought forward while on screen is no opening.
    func testOnlyAWindowComingOnScreenCountsAsAnOpening() {
        let selection = SettingsSelection()
        XCTAssertEqual(selection.openings, 0)

        selection.broughtUp(on: nil, alreadyOnScreen: false)
        XCTAssertEqual(selection.openings, 1)

        selection.broughtUp(on: .streamDeck, alreadyOnScreen: true)
        XCTAssertEqual(selection.openings, 1)

        selection.broughtUp(on: nil, alreadyOnScreen: false)
        XCTAssertEqual(selection.openings, 2)
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
