import XCTest
@testable import Claudio

/// The "Recent dictations" submenu: the way back to a dictation whose paste
/// landed in the wrong place, without a detour through Settings. A row that
/// holds the wrong text, cuts a character in half or stretches the menu
/// across the screen makes that way back worse than the detour.
final class RecentDictationsMenuTests: XCTestCase {

    /// The submenu's label is compared in French: the suite pins the language
    /// rather than inheriting it from the machine.
    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
        AppSettings.language = .french
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A history built the way the store builds it: oldest dictation first,
    /// each one pushed to the front.
    private func history(_ dictations: [(raw: String, cleaned: String?)]) -> RecentDictations {
        var recents = RecentDictations()
        for (index, dictation) in dictations.enumerated() {
            recents = recents.adding(RecentDictation(date: noon.addingTimeInterval(Double(index)),
                                                     language: .frFR,
                                                     raw: dictation.raw,
                                                     cleaned: dictation.cleaned))
        }
        return recents
    }

    // MARK: - Which dictations

    func testTheSubmenuIsCalledRecentDictations() {
        XCTAssertEqual(RecentDictationsMenu.menuTitle, "Dernières dictées")
    }

    /// Five rows, newest first: the dictation that just went astray is the
    /// top one. The rest of the history stays in Settings.
    func testTheFiveMostRecentDictationsAreListedNewestFirst() {
        let menu = RecentDictationsMenu(history((1...7).map { (raw: "dictée \($0)", cleaned: nil) }))
        XCTAssertEqual(menu.items.map(\.text),
                       ["dictée 7", "dictée 6", "dictée 5", "dictée 4", "dictée 3"])
    }

    func testNoDictationMeansNoRow() {
        XCTAssertTrue(RecentDictationsMenu(RecentDictations()).items.isEmpty)
    }

    /// A row pastes what the dictation pasted: the cleaned-up text when there
    /// was a cleanup, the transcript when there wasn't — the "Raw" model, or
    /// a cleanup that failed.
    func testARowHoldsWhatTheDictationPasted() {
        let menu = RecentDictationsMenu(history([
            (raw: "note pour moi rappeler le comptable", cleaned: nil),
            (raw: "euh bonjour à tous", cleaned: "Bonjour à tous."),
        ]))
        XCTAssertEqual(menu.items, [
            .init(title: "Bonjour à tous.", text: "Bonjour à tous."),
            .init(title: "note pour moi rappeler le comptable", text: "note pour moi rappeler le comptable"),
        ])
    }

    // MARK: - Titles

    func testAShortTextIsShownWhole() {
        XCTAssertEqual(RecentDictationsMenu.title(for: "Bonjour."), "Bonjour.")
        let fifty = String(repeating: "a", count: 50)
        XCTAssertEqual(RecentDictationsMenu.title(for: fifty), fifty)
    }

    /// A dictated paragraph has line breaks and a menu row has one line:
    /// every run of whitespace becomes a single space, none at either end.
    func testATitleIsASingleLine() {
        XCTAssertEqual(RecentDictationsMenu.title(for: "  Bonjour,\n\nje   voulais\tte dire\r\nmerci  "),
                       "Bonjour, je voulais te dire merci")
    }

    /// Past fifty characters the row would stretch the menu: it keeps
    /// forty-nine and says the rest exists with "…".
    func testALongTextIsCutWithAnEllipsis() {
        let title = RecentDictationsMenu.title(
            for: "Bonjour, je voulais te dire que la réunion de mercredi est décalée à quatorze heures.")
        XCTAssertEqual(title, "Bonjour, je voulais te dire que la réunion de mer…")
        XCTAssertEqual(title.count, 50)
    }

    func testACutAfterAWordLeavesNoSpaceBeforeTheEllipsis() {
        XCTAssertEqual(
            RecentDictationsMenu.title(for: "Bonjour, je voulais te dire que la réunion du 12 septembre est décalée."),
            "Bonjour, je voulais te dire que la réunion du 12…")
    }

    /// Characters as a reader counts them. An accent typed as a letter plus a
    /// combining mark, or a family emoji made of seven code points, falls on
    /// the forty-ninth character here: the cut keeps it whole rather than
    /// leaving a bare "e" or a lone parent before the "…".
    func testACutNeverSplitsAnAccentOrAnEmoji() {
        XCTAssertEqual(
            RecentDictationsMenu.title(for: "Bonjour, je voulais te dire que la réunion est de\u{301}cale\u{301}e à quatorze heures."),
            "Bonjour, je voulais te dire que la réunion est de\u{301}…")
        XCTAssertEqual(
            RecentDictationsMenu.title(for: "On se retrouve à la plage avec toute la famille 👨‍👩‍👧‍👦 samedi !"),
            "On se retrouve à la plage avec toute la famille 👨‍👩‍👧‍👦…")
    }
}
