import AppKit
import XCTest
@testable import Claudio

/// A click on a recent dictation: the text goes back to the cursor of the app
/// in front, by the same paste as a dictation — and never into Claudio, where
/// a synthetic ⌘V lands in whatever of its own has the keyboard. Played with
/// no permission, no pasteboard, no panel and no keystroke: every step is a
/// closure that only writes down that it ran.
@MainActor
final class RecentDictationPasterTests: XCTestCase {

    private let text = "Bonjour à tous."

    func testAClickPastesAtTheCursorOfTheAppInFront() async {
        let bench = PasterBench()
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps.last, .paste(text))
        XCTAssertFalse(bench.steps.contains(.copy(text)))
    }

    /// The order is the rule. The app in front is read first, while it still
    /// is: the permission alert brings Claudio forward. Claudio's panels leave
    /// the screen before the keystroke, because one still up has the keyboard
    /// and would take the ⌘V.
    func testTheTargetIsReadFirstAndThePanelsCloseBeforeTheKeystroke() async {
        let bench = PasterBench()
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .gate, .closePanels, .paste(text)])
    }

    /// Claudio itself in front — its Settings window, say — or no app at all:
    /// there is no other cursor to paste at. The clipboard takes the text
    /// instead, and a copy asks for no permission it doesn't need.
    func testWithNoOtherAppInFrontTheTextIsCopiedNotPasted() async {
        let bench = PasterBench(app: nil)
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .copy(text)])
    }

    /// Same gate as a dictation: without Accessibility the keystroke can't be
    /// sent, so nothing is — and nothing on screen is closed for it.
    func testWithoutAccessibilityNothingIsPasted() async {
        let bench = PasterBench(allowed: false)
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .gate])
    }
}

// MARK: - The bench

/// One paster built on fakes, and the steps it took, in order.
@MainActor
private final class PasterBench {
    enum Step: Equatable {
        case capture, gate, closePanels
        case paste(String), copy(String)
    }

    private(set) var steps: [Step] = []
    /// Built in `init` and never cleared: the tests see it as what it is.
    var paster: RecentDictationPaster { built }
    private var built: RecentDictationPaster!

    /// `app` is the one in front when the row is clicked, `nil` when it's
    /// Claudio; `allowed` is the Accessibility permission.
    init(app: NSRunningApplication? = .current, allowed: Bool = true) {
        built = RecentDictationPaster(
            pasting: PasteService(
                isAllowed: { [weak self] in
                    self?.steps.append(.gate)
                    return allowed
                },
                capture: { [weak self] in
                    self?.steps.append(.capture)
                    return PasteTarget(app: app, clipboard: nil)
                },
                paste: { [weak self] text, _ in
                    self?.steps.append(.paste(text))
                    return true
                }
            ),
            closePanels: { [weak self] in self?.steps.append(.closePanels) },
            copy: { [weak self] text in self?.steps.append(.copy(text)) },
            menuClosing: .zero
        )
    }
}
