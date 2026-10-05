import XCTest
@testable import Claudio

/// The rules of the Python hook that drove the clock before Claudio, ported
/// as they were: for each event, the commands sent to the clock, in order.
/// Same texts, colours, sounds and indicator; a wait forgotten after 12 h;
/// and the held alerts in the order they were posted, which is the order
/// the clock shows them in and the middle button takes them away in.
final class ClaudeCodeBoardTests: XCTestCase {

    private var board: ClaudeCodeBoard!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private let sessionA = "5f0c2a9e-aaaa-4bbb-8ccc-000000000001"
    private let sessionB = "77d1e3f0-aaaa-4bbb-8ccc-000000000002"
    private let sessionC = "c0ffee00-aaaa-4bbb-8ccc-000000000003"
    private let alertA = "cc-5f0c2a9e"
    private let alertB = "cc-77d1e3f0"

    private let orange = UlanziIndicator(color: "#FF851B", blinkMs: 0, fadeMs: 2000)
    private let red = UlanziIndicator(color: "#FF2D2D", blinkMs: 600, fadeMs: 0)

    override func setUp() {
        super.setUp()
        board = ClaudeCodeBoard()
    }

    override func tearDown() {
        board = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func event(_ kind: ClaudeCodeEvent.Kind, _ session: String? = nil,
                       cwd: String? = "/Users/g/Documents/claude/BAGUETTE",
                       message: String? = nil) -> ClaudeCodeEvent {
        ClaudeCodeEvent(kind: kind, sessionID: session ?? sessionA, cwd: cwd, lastAssistantMessage: message)
    }

    private func stop(_ message: String?, _ session: String? = nil) -> ClaudeCodeEvent {
        event(.stop, session, message: message)
    }

    @discardableResult
    private func handle(_ event: ClaudeCodeEvent, at time: Date? = nil) -> [UlanziCommand] {
        board.handle(event, now: time ?? t0)
    }

    // MARK: - Stop, flag by flag

    /// 🟩: the project and FINI for six seconds, with the rising scale. The
    /// session's own alert goes first; the first indicator is always sent.
    func testAStopDoneShowsFiniForSixSecondsWithItsScale() {
        XCTAssertEqual(handle(stop("🟩 **FINI — livré**")), [
            .dismiss(name: alertA),
            .notify(UlanziNotification(text: "BAGUETTE FINI", textColor: "#2ECC40", durationMs: 6000,
                                       soundRtttl: "fini:d=16,o=5,b=140:c,d,e,f,g,a,b,c6")),
            .indicator(nil),
        ])
        XCTAssertEqual(board.alerts, [])
    }

    /// 🟦: INFO for four seconds, without a sound.
    func testAStopInfoShowsInfoForFourSecondsSilently() {
        XCTAssertEqual(handle(stop("🟦 INFO")), [
            .dismiss(name: alertA),
            .notify(UlanziNotification(text: "BAGUETTE INFO", textColor: "#3D9BFF", durationMs: 4000)),
            .indicator(nil),
        ])
    }

    /// 🟧: DÉCISION held under the session's name, waking the screen, and
    /// the indicator breathes orange.
    func testAStopDecisionHoldsTheAlertAndBreathesOrange() {
        XCTAssertEqual(handle(stop("🟧 DÉCISION")), [
            .dismiss(name: alertA),
            .notify(UlanziNotification(name: alertA, text: "BAGUETTE DÉCISION", textColor: "#FF851B",
                                       hold: true, wakeup: true, soundRtttl: "dec:d=16,o=5,b=140:g,p,g,8c6")),
            .indicator(orange),
        ])
        XCTAssertEqual(board.alerts, [ClaudeCodeBoard.Alert(name: alertA, sessionID: sessionA)])
    }

    /// 🟥: BLOCAGE held and blinking, and the indicator blinks red.
    func testAStopBlockedHoldsABlinkingAlertAndBlinksRed() {
        XCTAssertEqual(handle(stop("🟥 BLOCAGE")), [
            .dismiss(name: alertA),
            .notify(UlanziNotification(name: alertA, text: "BAGUETTE BLOCAGE", textColor: "#FF2D2D",
                                       hold: true, wakeup: true, textBlinkMs: 600,
                                       soundRtttl: "blk:d=16,o=5,b=140:g,f#,f,8e")),
            .indicator(red),
        ])
        XCTAssertEqual(board.alerts, [ClaudeCodeBoard.Alert(name: alertA, sessionID: sessionA)])
    }

    /// A short answer without a flag: the project's name winks in grey, in
    /// silence.
    func testAStopWithoutAFlagWinksTheProjectsName() {
        XCTAssertEqual(handle(stop("Oui.")), [
            .dismiss(name: alertA),
            .notify(UlanziNotification(text: "BAGUETTE", textColor: "#AAAAAA", durationMs: 1500)),
            .indicator(nil),
        ])
        XCTAssertEqual(Array(handle(stop(nil)).dropFirst()),
                       [.notify(UlanziNotification(text: "BAGUETTE", textColor: "#AAAAAA", durationMs: 1500))])
    }

    /// A session that stops again takes its own held alert away before
    /// anything else: the turn it was waiting on is over.
    func testAStopTakesTheSessionsHeldAlertAway() {
        handle(stop("🟧 DÉCISION"))

        XCTAssertEqual(handle(stop("🟩 FINI")).first, .dismiss(name: alertA))
        XCTAssertEqual(board.alerts, [])
        XCTAssertEqual(handle(stop("🟩 FINI")).last, .notify(UlanziNotification(
            text: "BAGUETTE FINI", textColor: "#2ECC40", durationMs: 6000,
            soundRtttl: "fini:d=16,o=5,b=140:c,d,e,f,g,a,b,c6")))
    }

    // MARK: - Notifications

    /// Each of the five waits holds the project and a question mark, in
    /// orange, with the waiting tune, and lights the indicator orange.
    func testEveryWaitingNotificationHoldsAQuestionMark() {
        for type in ["permission_prompt", "idle_prompt", "agent_needs_input",
                     "elicitation_dialog", "elicitation_url_dialog"] {
            board = ClaudeCodeBoard()
            XCTAssertEqual(handle(event(.notification(type: type))), [
                .notify(UlanziNotification(name: alertA, text: "BAGUETTE ?", textColor: "#FF851B",
                                           hold: true, wakeup: true, soundRtttl: "att:d=16,o=5,b=140:e,p,e,p,8a")),
                .indicator(orange),
            ], type)
            XCTAssertEqual(board.alerts, [ClaudeCodeBoard.Alert(name: alertA, sessionID: sessionA)], type)
        }
    }

    /// Another notification, or another hook, shows nothing and sends
    /// nothing, the indicator included.
    func testAnyOtherEventSendsNothing() {
        XCTAssertEqual(handle(event(.notification(type: "auth_success"))), [])
        XCTAssertEqual(handle(event(.notification(type: ""))), [])
        XCTAssertEqual(handle(event(.other)), [])
        XCTAssertEqual(board.alerts, [])
    }

    // MARK: - Answering

    /// Guillaume answers in the session, or the session ends: its alert
    /// goes, and the indicator with it when nothing else waits.
    func testAPromptOrAnEndTakesTheAlertAway() {
        for kind in [ClaudeCodeEvent.Kind.promptSubmitted, .sessionEnded] {
            board = ClaudeCodeBoard()
            handle(stop("🟧 DÉCISION"))

            XCTAssertEqual(handle(event(kind)), [.dismiss(name: alertA), .indicator(nil)], "\(kind)")
            XCTAssertEqual(board.alerts, [], "\(kind)")
        }
    }

    /// A prompt in a session that wasn't waiting still dismisses its name:
    /// the clock may hold an alert this board never knew of.
    func testAPromptWithNothingHeldStillDismisses() {
        XCTAssertEqual(handle(event(.promptSubmitted)), [.dismiss(name: alertA), .indicator(nil)])
    }

    // MARK: - The indicator

    /// Sent the first time whatever it is, then only when it changes: red as
    /// soon as one session is blocked, orange while one waits, off after.
    func testTheIndicatorIsOnlySentWhenItChanges() {
        XCTAssertEqual(handle(stop("🟩", sessionA)).last, .indicator(nil))
        XCTAssertEqual(handle(stop("🟦", sessionB)).last,
                       .notify(UlanziNotification(text: "BAGUETTE INFO", textColor: "#3D9BFF", durationMs: 4000)))
        XCTAssertEqual(handle(stop("🟧", sessionA)).last, .indicator(orange))
        XCTAssertEqual(handle(event(.notification(type: "permission_prompt"), sessionB)).count, 1)
        XCTAssertEqual(handle(stop("🟥", sessionC)).last, .indicator(red))
        XCTAssertEqual(handle(event(.notification(type: "idle_prompt"), sessionA)).count, 1)
        XCTAssertEqual(handle(event(.promptSubmitted, sessionC)).last, .indicator(orange))
        XCTAssertEqual(handle(event(.promptSubmitted, sessionA)), [.dismiss(name: alertA)])
        XCTAssertEqual(handle(event(.sessionEnded, sessionB)), [.dismiss(name: alertB), .indicator(nil)])
    }

    /// An indicator the clock may not have taken goes again at the next
    /// change of state, unchanged or not: only what landed is remembered.
    func testAnIndicatorThatFailedGoesAgain() {
        handle(stop("🟧", sessionA))
        board.indicatorFailed()

        XCTAssertEqual(handle(event(.notification(type: "permission_prompt"), sessionB)).last, .indicator(orange))
        XCTAssertEqual(handle(event(.notification(type: "permission_prompt"), sessionB)).count, 1)
    }

    /// A session killed without a SessionEnd doesn't keep the indicator on:
    /// past 12 h its wait is forgotten. Its alert stays in the queue, as it
    /// stays on the clock until a press takes it away.
    func testAWaitOlderThanTwelveHoursIsForgotten() {
        handle(stop("🟧", sessionA), at: t0)
        let twelveHours: TimeInterval = 12 * 3600

        XCTAssertEqual(handle(stop("🟩", sessionB), at: t0 + twelveHours - 1).last,
                       .notify(UlanziNotification(text: "BAGUETTE FINI", textColor: "#2ECC40", durationMs: 6000,
                                                  soundRtttl: "fini:d=16,o=5,b=140:c,d,e,f,g,a,b,c6")))
        XCTAssertEqual(handle(stop("🟩", sessionB), at: t0 + twelveHours).last, .indicator(nil))
        XCTAssertEqual(board.alerts, [ClaudeCodeBoard.Alert(name: alertA, sessionID: sessionA)])
    }

    /// A wait asked again starts its twelve hours again.
    func testAWaitAskedAgainStartsItsTwelveHoursAgain() {
        handle(stop("🟧", sessionA), at: t0)
        handle(event(.notification(type: "permission_prompt"), sessionA), at: t0 + 11 * 3600)

        XCTAssertEqual(handle(stop("🟩", sessionB), at: t0 + 13 * 3600).count, 2)
    }

    // MARK: - The middle button

    /// The clock shows the oldest held alert, and the button takes that one
    /// away: first A, then B, then nothing. Each press says whose it was.
    func testTheButtonTakesTheHeldAlertsAwayOldestFirst() {
        handle(stop("🟧", sessionA))
        handle(stop("🟥", sessionB))

        let first = board.middleButtonPressed(now: t0)
        XCTAssertEqual(first.commands, [.dismiss(name: alertA)])
        XCTAssertEqual(first.sessionID, sessionA)

        let second = board.middleButtonPressed(now: t0)
        XCTAssertEqual(second.commands, [.dismiss(name: alertB), .indicator(nil)])
        XCTAssertEqual(second.sessionID, sessionB)

        let third = board.middleButtonPressed(now: t0)
        XCTAssertEqual(third.commands, [])
        XCTAssertNil(third.sessionID)
    }

    /// A press frees the session from its wait: the indicator follows.
    func testThePressFreesTheSessionsWait() {
        handle(stop("🟥", sessionA))
        handle(stop("🟧", sessionB))

        XCTAssertEqual(board.middleButtonPressed(now: t0).commands, [.dismiss(name: alertA), .indicator(orange)])
    }

    /// The same name posted again replaces the alert on the clock, and goes
    /// to the back of its queue: here as there.
    func testAnAlertPostedAgainGoesToTheBack() {
        handle(event(.notification(type: "permission_prompt"), sessionA))
        handle(event(.notification(type: "permission_prompt"), sessionB))
        handle(event(.notification(type: "idle_prompt"), sessionA))

        XCTAssertEqual(board.alerts.map(\.name), [alertB, alertA])
        XCTAssertEqual(board.middleButtonPressed(now: t0).sessionID, sessionB)
    }

    /// Nothing held: the press does nothing, and opens nothing.
    func testThePressWithNothingHeldDoesNothing() {
        XCTAssertEqual(board.middleButtonPressed(now: t0).commands, [])
        handle(stop("🟩"))
        let press = board.middleButtonPressed(now: t0)
        XCTAssertEqual(press.commands, [])
        XCTAssertNil(press.sessionID)
    }

    // MARK: - Names

    /// The project is the folder's last name, twelve characters at most, in
    /// capitals; CLAUDE when there is none.
    func testTheProjectIsTheFoldersNameInCapitals() {
        XCTAssertEqual(ClaudeCodeBoard.project(of: "/Users/g/Documents/claude/BAGUETTE"), "BAGUETTE")
        XCTAssertEqual(ClaudeCodeBoard.project(of: "/Users/g/claudio-ops//"), "CLAUDIO-OPS")
        XCTAssertEqual(ClaudeCodeBoard.project(of: "/x/une-tres-longue-racine"), "UNE-TRES-LON")
        XCTAssertEqual(ClaudeCodeBoard.project(of: "relatif"), "RELATIF")
        XCTAssertEqual(ClaudeCodeBoard.project(of: "/"), "CLAUDE")
        XCTAssertEqual(ClaudeCodeBoard.project(of: ""), "CLAUDE")
        XCTAssertEqual(ClaudeCodeBoard.project(of: nil), "CLAUDE")
    }

    /// The held alert is named after the session's first eight characters.
    func testTheAlertIsNamedAfterTheSession() {
        XCTAssertEqual(ClaudeCodeBoard.alertName(for: sessionA), "cc-5f0c2a9e")
        XCTAssertEqual(ClaudeCodeBoard.alertName(for: "abc"), "cc-abc")
    }
}
