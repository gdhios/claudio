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
    private let alertC = "cc-c0ffee00"

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

    /// What the hub tells the board once the clock has answered: every
    /// dismissal and every hold among `commands` landed, but those of the
    /// names in `failing`, which the clock never heard of. Returns what the
    /// board then has to send.
    @discardableResult
    private func deliver(_ commands: [UlanziCommand], failing: Set<String> = []) -> [UlanziCommand] {
        var then: [UlanziCommand] = []
        for command in commands {
            switch command {
            case .dismiss(let name) where failing.contains(name):
                board.dismissFailed(name: name)
            case .dismiss(let name):
                board.dismissLanded(name: name)
            case .notify(let notification):
                guard let name = notification.name else { continue }
                if failing.contains(name) {
                    then += board.notifyFailed(name: name, now: t0)
                } else {
                    board.notifyLanded(name: name)
                }
            case .indicator:
                continue
            }
        }
        return then
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

    // MARK: - A dismissal the clock never heard of

    /// The clock was out of reach when A answered: it still shows A's alert,
    /// so A goes back at the head of the queue, and the next press takes it
    /// for real, its own dismissal failing or not.
    func testAFailedDismissalPutsTheAlertBackAtTheHead() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(stop("🟥", sessionB)))

        deliver(handle(event(.promptSubmitted, sessionA)), failing: [alertA])
        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB])

        let press = board.middleButtonPressed(now: t0)
        XCTAssertEqual(press.sessionID, sessionA)
        XCTAssertEqual(press.commands, [.dismiss(name: alertA)])
        deliver(press.commands, failing: [alertA])
        XCTAssertEqual(board.alerts.map(\.name), [alertB])
    }

    /// Between two others, it goes back between the same two.
    func testAnAlertPutBackKeepsItsPlace() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(stop("🟧", sessionB)))
        deliver(handle(stop("🟧", sessionC)))

        deliver(handle(event(.sessionEnded, sessionB)), failing: [alertB])

        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB, alertC])
    }

    /// A dismissal the clock took is done for good.
    func testALandedDismissalIsDone() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(event(.promptSubmitted, sessionA)))
        board.dismissFailed(name: alertA)

        XCTAssertEqual(board.alerts, [])
    }

    /// Held again since under the same name, the clock replaced the old
    /// alert with the new one: nothing goes back.
    func testANameHeldAgainIsNotPutBack() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(stop("🟧", sessionB)))
        let dismissal = handle(event(.promptSubmitted, sessionA))
        handle(event(.notification(type: "permission_prompt"), sessionA))

        deliver(dismissal, failing: [alertA])

        XCTAssertEqual(board.alerts.map(\.name), [alertB, alertA])
    }

    /// Two dismissals of one name on their way: the last one decides. Both
    /// failing, the alert the clock still shows goes back; the second one
    /// landing, it is gone.
    func testTheLastOfTwoDismissalsOfANameDecides() {
        for secondLands in [false, true] {
            board = ClaudeCodeBoard()
            deliver(handle(stop("🟧", sessionA)))
            let prompt = handle(event(.promptSubmitted, sessionA))
            let stop = handle(stop("🟩", sessionA))

            deliver(prompt, failing: [alertA])
            XCTAssertEqual(board.alerts, [], "second lands: \(secondLands)")
            deliver(stop, failing: secondLands ? [] : [alertA])
            XCTAssertEqual(board.alerts.map(\.name), secondLands ? [] : [alertA], "second lands: \(secondLands)")
        }
    }

    /// A press while a dismissal of the same name is on its way: the press
    /// has the last word, and nothing comes back.
    func testAPressAfterAFailedDismissalPutsNothingBack() {
        deliver(handle(stop("🟧", sessionA)))
        let prompt = handle(event(.promptSubmitted, sessionA))
        handle(event(.notification(type: "permission_prompt"), sessionA))
        let press = board.middleButtonPressed(now: t0)

        deliver(prompt, failing: [alertA])
        deliver(press.commands, failing: [alertA])

        XCTAssertEqual(board.alerts, [])
    }

    // MARK: - A hold the clock never heard of

    /// The clock was out of reach when A ended on 🟧: its alert never made
    /// it, so it leaves the queue, and A waits no more, the indicator going
    /// out at once. B's 🟧 lands after it: the press takes B, and opens B.
    func testAHoldThatFailedLeavesTheQueueAndTheWait() {
        XCTAssertEqual(deliver(handle(stop("🟧", sessionA)), failing: [alertA]), [.indicator(nil)])
        XCTAssertEqual(board.alerts, [])
        XCTAssertNil(board.waits[sessionA])

        deliver(handle(stop("🟧", sessionB)))
        let press = board.middleButtonPressed(now: t0)

        XCTAssertEqual(press.sessionID, sessionB)
        XCTAssertEqual(press.commands, [.dismiss(name: alertB), .indicator(nil)])
    }

    /// A hold the clock took is there for good: an answer with nothing on
    /// its way changes nothing.
    func testALandedHoldStays() {
        deliver(handle(stop("🟥", sessionA)))

        XCTAssertEqual(board.notifyFailed(name: alertA, now: t0), [])
        XCTAssertEqual(board.alerts.map(\.name), [alertA])
        XCTAssertEqual(board.waits[sessionA]?.level, .red)
    }

    /// Held again since under the same name, the newer hold wins: the alert
    /// stays, and so does the wait, the indicator unchanged.
    func testANewerHoldOfTheSameNameWins() {
        let decision = handle(stop("🟧", sessionA))
        let question = handle(event(.notification(type: "permission_prompt"), sessionA))

        XCTAssertEqual(deliver(decision, failing: [alertA]), [])
        XCTAssertEqual(board.alerts.map(\.name), [alertA])
        XCTAssertNotNil(board.waits[sessionA])
        deliver(question)
        XCTAssertEqual(board.middleButtonPressed(now: t0).sessionID, sessionA)
    }

    /// A hold under a name the clock shows already, and never heard of: the
    /// clock still shows the alert it was to replace, where it was. It goes
    /// back there, the session still waiting on it.
    func testAHoldThatFailedGivesBackTheAlertItReplaced() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(stop("🟧", sessionB)))

        XCTAssertEqual(deliver(handle(event(.notification(type: "idle_prompt"), sessionA)), failing: [alertA]), [])

        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB])
        XCTAssertNotNil(board.waits[sessionA])
        XCTAssertEqual(board.middleButtonPressed(now: t0).sessionID, sessionA)
    }

    /// A Stop the clock never heard of, neither its dismissal nor its hold:
    /// the session's question is still on screen, ahead of B's, and the
    /// press opens A.
    func testAStopThatNeverReachedTheClockKeepsTheEarlierAlert() {
        deliver(handle(event(.notification(type: "permission_prompt"), sessionA)))
        deliver(handle(stop("🟧", sessionB)))

        deliver(handle(stop("🟧", sessionA)), failing: [alertA])

        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB])
        XCTAssertEqual(board.middleButtonPressed(now: t0).sessionID, sessionA)
    }

    /// An alert that never made it doesn't come back with a dismissal that
    /// failed after it: there was nothing on the clock to dismiss.
    func testAnAlertThatNeverMadeItDoesNotComeBack() {
        let decision = handle(stop("🟧", sessionA))
        let prompt = handle(event(.promptSubmitted, sessionA))

        deliver(decision, failing: [alertA])
        deliver(prompt, failing: [alertA])

        XCTAssertEqual(board.alerts, [])
    }

    /// A press while the hold is still on its way: the firmware took the
    /// alert off the screen, and the hold landing after brings nothing
    /// back, the press's own dismissal failing or not.
    func testAPressHasTheLastWordOverAHoldOnItsWay() {
        let decision = handle(stop("🟧", sessionA))
        let press = board.middleButtonPressed(now: t0)

        deliver(decision)
        deliver(press.commands, failing: [alertA])

        XCTAssertEqual(board.alerts, [])
    }

    // MARK: - Outliving Claudio

    /// What outlives Claudio: the alerts the clock said it holds, in their
    /// places, and who waits since when. A hold still on its way is not in
    /// it, no answer coming for it after a restart; its wait is.
    func testASnapshotKeepsWhatTheClockHoldsAndWhoWaits() {
        deliver(handle(stop("🟧", sessionA), at: t0))
        deliver(handle(stop("🟥", sessionB), at: t0 + 60))
        handle(event(.notification(type: "permission_prompt"), sessionC))

        XCTAssertEqual(board.snapshot.held, [
            ClaudeCodeBoard.Snapshot.Held(name: alertA, sessionID: sessionA, order: 0),
            ClaudeCodeBoard.Snapshot.Held(name: alertB, sessionID: sessionB, order: 1),
        ])
        XCTAssertEqual(board.snapshot.waits, [
            ClaudeCodeBoard.Snapshot.Waiting(sessionID: sessionA, level: .orange, since: t0),
            ClaudeCodeBoard.Snapshot.Waiting(sessionID: sessionB, level: .red, since: t0 + 60),
            ClaudeCodeBoard.Snapshot.Waiting(sessionID: sessionC, level: .orange, since: t0),
        ])
    }

    /// Restored, the board takes up where it stopped: the same alerts in the
    /// same order, the same waits, the indicator sent whatever it is, and an
    /// alert posted again going to the back.
    func testARestoredBoardTakesUpWhereItStopped() {
        deliver(handle(stop("🟧", sessionA)))
        deliver(handle(stop("🟥", sessionB)))

        board = ClaudeCodeBoard(restoring: board.snapshot, now: t0)

        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB])
        XCTAssertEqual(board.waits[sessionB]?.level, .red)
        XCTAssertEqual(handle(stop("🟩", sessionC)).last, .indicator(red))
        handle(event(.notification(type: "permission_prompt"), sessionA))
        XCTAssertEqual(board.alerts.map(\.name), [alertB, alertA])
    }

    /// A wait twelve hours old by the restart is forgotten; its alert, still
    /// on the clock, is not.
    func testARestoredBoardForgetsTheWaitsPastTwelveHours() {
        deliver(handle(stop("🟧", sessionA), at: t0))
        deliver(handle(stop("🟧", sessionB), at: t0 + 60))

        board = ClaudeCodeBoard(restoring: board.snapshot, now: t0 + 12 * 3600)

        XCTAssertNil(board.waits[sessionA])
        XCTAssertNotNil(board.waits[sessionB])
        XCTAssertEqual(board.alerts.map(\.name), [alertA, alertB])
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
