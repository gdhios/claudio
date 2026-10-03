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
        XCTAssertTrue(bench.steps.contains(.paste(text)))
        XCTAssertFalse(bench.steps.contains(.copy(text)))
    }

    /// The paste leaves the text on the clipboard instead of putting the old
    /// contents back: a ⌘V that found no field to land in used to leave no
    /// trace at all, and the click looked like it did nothing.
    func testThePastedTextStaysOnTheClipboard() async {
        let bench = PasterBench()
        await bench.paster.paste(text)
        XCTAssertEqual(bench.restoredClipboards, [false])
    }

    /// Each click says what it did, once the text is where it goes.
    func testAPasteIsAnnouncedAfterTheKeystroke() async {
        let bench = PasterBench()
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps.suffix(2), [.paste(text), .announce(.pasted)])
    }

    func testACopyIsAnnouncedAsACopy() async {
        let bench = PasterBench(app: nil)
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps.last, .announce(.copied))
    }

    /// The order is the rule. The app in front is read first, while it still
    /// is: the permission alert brings Claudio forward. Claudio's panels leave
    /// the screen before the keystroke, because one still up has the keyboard
    /// and would take the ⌘V.
    func testTheTargetIsReadFirstAndThePanelsCloseBeforeTheKeystroke() async {
        let bench = PasterBench()
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .gate, .closePanels, .paste(text), .announce(.pasted)])
    }

    /// Claudio itself in front — its Settings window, say — or no app at all:
    /// there is no other cursor to paste at. The clipboard takes the text
    /// instead, and a copy asks for no permission it doesn't need.
    func testWithNoOtherAppInFrontTheTextIsCopiedNotPasted() async {
        let bench = PasterBench(app: nil)
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .copy(text), .announce(.copied)])
    }

    /// Same gate as a dictation: without Accessibility the keystroke can't be
    /// sent, so nothing is — and nothing on screen is closed for it. The
    /// clipboard still gets the text: a click always leaves it somewhere.
    func testWithoutAccessibilityTheTextIsCopiedNotPasted() async {
        let bench = PasterBench(allowed: false)
        await bench.paster.paste(text)
        XCTAssertEqual(bench.steps, [.capture, .gate, .copy(text), .announce(.copied)])
    }
}

// MARK: - The bench

/// One paster built on fakes, and the steps it took, in order.
@MainActor
private final class PasterBench {
    enum Step: Equatable {
        case capture, gate, closePanels
        case paste(String), copy(String)
        case announce(RecentDictationOutcome)
    }

    private(set) var steps: [Step] = []
    /// For each paste, whether it was told to put the old clipboard back.
    private(set) var restoredClipboards: [Bool] = []
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
                    // A clipboard to put back, as the real capture takes:
                    // the paster is the one that must decline it. Read only.
                    return PasteTarget(app: app, clipboard: PasteboardSnapshot.capture())
                },
                paste: { [weak self] text, target in
                    self?.steps.append(.paste(text))
                    self?.restoredClipboards.append(target.clipboard != nil)
                }
            ),
            closePanels: { [weak self] in self?.steps.append(.closePanels) },
            copy: { [weak self] text in self?.steps.append(.copy(text)) },
            announce: { [weak self] outcome in self?.steps.append(.announce(outcome)) },
            menuClosing: .zero
        )
    }
}
