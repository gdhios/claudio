import XCTest
@testable import Claudio

/// What the clock is told, and when. The device draws and animates the face
/// itself; the bridge only has to install it, then send a gaze each time the
/// one Claudio wears changes, summoning the face when it comes back from off.
/// Every gaze costs the device a restart of the script, so a gaze already
/// there is never sent twice, and a send that failed is never taken for one
/// that landed: it is tried once more, a moment later.
///
/// The sessions are real, the device is `FakeUlanzi` and time is a
/// `ManualClock`: no socket is opened, and only a failing test meets the
/// wall clock, at the ceiling that keeps it from hanging the suite.
@MainActor
final class UlanziBridgeTests: XCTestCase, AsyncWaiting {

    private let address = URL(string: "http://192.168.1.22")!
    private var device = FakeUlanzi()
    private var statuses: [UlanziBridge.Status] = []
    private lazy var clock = ManualClock()

    /// Calls the device the test has when it starts, whichever that is.
    private lazy var bridge: UlanziBridge = {
        let bridge = UlanziBridge(client: { [unowned self] in UlanziClient(baseURL: $0, transport: device.transport) },
                                  sleep: { [clock] in try await clock.sleep(for: $0) })
        bridge.onStatusChange = { [unowned self] in statuses.append($0) }
        return bridge
    }()

    private let install = "PUT /api/v1/apps/script/Claudio"
    private let read = "GET /api/v1/apps/script/Claudio"
    private let gaze = "PATCH /api/v1/apps/Claudio/config"
    private let summon = "PUT /api/v1/apps/active"

    /// The gazes the device was asked for, in order.
    private var gazesSent: [String] {
        device.requests.filter { $0.method == "PATCH" }.map { request in
            let object = try? JSONSerialization.jsonObject(with: Data(request.body.utf8)) as? [String: String]
            return object?["gaze"] ?? "?"
        }
    }

    /// Lets the publisher's deferred refresh run: it is on the main actor,
    /// and a few turns are all it needs.
    private func turns() async {
        for _ in 0..<3 { await Task.yield() }
    }

    /// The publisher's refresh, then everything the bridge has queued for the
    /// device, sends queued meanwhile included.
    private func settle() async {
        await turns()
        while let tail = bridge.sending {
            await tail.value
            if bridge.sending == tail { break }
        }
    }

    private func dictating(_ phase: DictationSession.Phase = .listening) -> DictationSession {
        let session = DictationSession(language: .frFR, model: .raw)
        session.phase = phase
        return session
    }

    /// Started on a device that has the face already, and settled: the
    /// starting point of most tests, its requests forgotten.
    private func startedOnAReadyDevice() async {
        device = FakeUlanzi(script: UlanziFaceScript.source)
        bridge.start(address: address)
        await settle()
        device.clearRequests()
    }

    /// A dictation listening, its face on the clock, the requests forgotten.
    private func startedWithAFaceUp() async -> DictationSession {
        await startedOnAReadyDevice()
        let session = dictating()
        bridge.dictationSessionChanged(session)
        await settle()
        device.clearRequests()
        return session
    }

    // MARK: - The gaze each state asks for

    /// Claudio waiting is no face at all: the clock goes back to its rotation.
    func testIdleIsOff() {
        XCTAssertEqual(UlanziBridge.gazeName(for: .idle), "off")
    }

    /// At work, the gaze travels under the name the script knows it by, the
    /// mascot's own raw value, whatever he is working on.
    func testEveryGazeTravelsUnderItsRawValue() {
        for gaze in ClaudioMascot.Gaze.allCases {
            for activity in [BridgeState.Activity.correction, .dictation] {
                let state = BridgeState(gaze: gaze, activity: activity, phase: nil, label: nil, locked: false)
                XCTAssertEqual(UlanziBridge.gazeName(for: state), gaze.rawValue)
            }
        }
    }

    // MARK: - Coming on

    /// A clock that never had the face gets it, then is told to keep it
    /// hidden: a face left up by a crash goes at launch.
    func testComingOnInstallsTheFaceThenPutsItAway() async {
        bridge.start(address: address)
        await settle()

        XCTAssertEqual(device.calls, [read, install, gaze])
        XCTAssertEqual(device.script, UlanziFaceScript.source)
        XCTAssertEqual(gazesSent, ["off"])
        XCTAssertEqual(bridge.status, .ready)
    }

    /// The face already there, to the byte, is not sent again.
    func testAFaceAlreadyThereIsNotSentAgain() async {
        device = FakeUlanzi(script: UlanziFaceScript.source)
        bridge.start(address: address)
        await settle()

        XCTAssertEqual(device.calls, [read, gaze])
    }

    /// An older face, from an earlier version of the script, is replaced.
    func testAnOlderFaceIsReplaced() async {
        device = FakeUlanzi(script: "# @name    Claudio\n# @version 0.9\nreturn 0\n")
        bridge.start(address: address)
        await settle()

        XCTAssertEqual(device.calls, [read, install, gaze])
        XCTAssertEqual(device.script, UlanziFaceScript.source)
    }

    /// Settings says what is happening while it happens.
    func testTheStatusSaysInstallingUntilTheDeviceIsReady() async {
        bridge.start(address: address)
        XCTAssertEqual(bridge.status, .installing)
        await settle()

        XCTAssertEqual(statuses, [.installing, .ready])
    }

    /// A face the clock can't run is an error, in the clock's own words, and
    /// not a clock out of reach.
    func testAFaceTheClockCannotRunIsAnError() async {
        device.scriptError = "syntax_error: unexpected 'end'"
        bridge.start(address: address)
        await settle()

        XCTAssertEqual(bridge.status, .failed(.scriptBroken("syntax_error: unexpected 'end'")))
    }

    /// Switched on mid-dictation, the bridge shows the dictation: the hooks
    /// only report changes, and this one was announced before it started.
    /// The session is held here as its coordinator would hold it; the bridge
    /// only keeps it weakly.
    func testABridgeSwitchedOnMidDictationShowsIt() async {
        let session = dictating()
        bridge.dictationSessionChanged(session)
        bridge.start(address: address)
        await settle()

        XCTAssertEqual(device.calls, [read, install, gaze, gaze, summon])
        XCTAssertEqual(gazesSent, ["off", "repos"])
        XCTAssertEqual(session.phase, .listening)
    }

    /// A session announced while the bridge was off, and gone since, is
    /// nobody's to keep: the bridge doesn't hold a finished dictation, and
    /// switched on later it shows nothing.
    func testASessionGoneBeforeTheStartIsNotShown() async {
        weak var released: DictationSession?
        do {
            let session = dictating()
            released = session
            bridge.dictationSessionChanged(session)
        }
        bridge.start(address: address)
        await settle()

        XCTAssertNil(released)
        XCTAssertEqual(gazesSent, ["off"])
    }

    // MARK: - Following Claudio

    /// From off, the gaze is set first and the face summoned after: summoned
    /// first, it would show the gaze it had before.
    func testADictationSetsTheGazeThenSummonsTheFace() async {
        await startedOnAReadyDevice()

        bridge.dictationSessionChanged(dictating())
        await settle()

        XCTAssertEqual(device.calls, [gaze, summon])
        XCTAssertEqual(device.gaze, "repos")
    }

    /// The face is up: a new gaze only restarts the script in its place.
    func testAGazeChangeWithTheFaceUpOnlySetsTheGaze() async {
        let session = await startedWithAFaceUp()

        session.phase = .cleaning
        await settle()

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(gazesSent, ["veille"])
    }

    /// A tap locking the dictation changes the state but not the gaze: the
    /// device, which would restart the script for nothing, hears nothing.
    func testTheSameGazeIsNotSentTwice() async {
        let session = await startedWithAFaceUp()

        session.isLocked = true
        await settle()

        XCTAssertEqual(device.calls, [])
    }

    /// The dictation over, the face goes away; nothing is summoned for off.
    func testTheEndOfADictationPutsTheFaceAway() async {
        _ = await startedWithAFaceUp()

        bridge.dictationSessionChanged(nil)
        await settle()

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(device.gaze, "off")
    }

    /// The microphone's loudness moves dozens of times a second and every
    /// config change restarts the script: it never reaches the clock.
    func testTheMicrophoneLevelNeverReachesTheDevice() async {
        let session = await startedWithAFaceUp()

        for reading: Float in [0.2, 0.6, 0.9] {
            session.levels = session.levels.adding(reading)
            await settle()
        }

        XCTAssertEqual(device.calls, [])
    }

    /// Gazes coming while the device still hasn't answered wait their turn:
    /// it hears them one at a time, in the order Claudio wore them.
    func testGazesArrivingMidSendWaitTheirTurn() async {
        await startedOnAReadyDevice()
        device.holdAnswers()
        let session = dictating()

        bridge.dictationSessionChanged(session)
        await device.waitUntilReceived(1)
        session.phase = .cleaning
        await turns()
        session.phase = .done
        await turns()
        XCTAssertEqual(device.calls, [gaze], "nothing overtakes a request in flight")

        device.releaseAnswers()
        await settle()

        XCTAssertEqual(device.calls, [gaze, summon, gaze, gaze])
        XCTAssertEqual(gazesSent, ["repos", "veille", "fait"])
        XCTAssertEqual(device.mostRequestsAtOnce, 1)
    }

    // MARK: - When the device doesn't answer

    /// Unplugged at launch: Settings says so, and the next change in Claudio
    /// tries again, from the installation on.
    func testAnUnreachableDeviceIsReportedThenRetried() async {
        device.isUnplugged = true
        bridge.start(address: address)
        await settle()
        guard case .failed(.unreachable(let reason)) = bridge.status else {
            return XCTFail("expected the device out of reach, got \(bridge.status)")
        }
        XCTAssertFalse(reason.isEmpty)

        device.isUnplugged = false
        device.clearRequests()
        bridge.dictationSessionChanged(dictating())
        await settle()

        XCTAssertEqual(device.calls, [read, install, gaze, summon])
        XCTAssertEqual(device.gaze, "repos")
        XCTAssertEqual(bridge.status, .ready)
    }

    /// A gaze the device refused is not taken for one it shows: the next
    /// state tries it again, even when it asks for the same gaze. Settings
    /// shows the device's message.
    func testARefusedGazeIsTriedAgainAtTheNextState() async {
        await startedOnAReadyDevice()
        device.answer(gaze, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        let session = dictating()
        bridge.dictationSessionChanged(session)
        await settle()
        XCTAssertEqual(bridge.status, .failed(.rejected(status: 503, message: "busy")))

        device.forget(gaze)
        device.clearRequests()
        session.isLocked = true
        await settle()

        XCTAssertEqual(device.calls, [read, gaze, summon])
        XCTAssertEqual(device.gaze, "repos")
        XCTAssertEqual(bridge.status, .ready)
    }

    /// Claudio doesn't move, the device was only busy: the gaze is tried
    /// once more a moment later, without waiting for a change.
    func testAFailedGazeIsTriedAgainAMomentLater() async {
        await startedOnAReadyDevice()
        device.answer(gaze, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        let session = dictating()
        bridge.dictationSessionChanged(session)
        await settle()
        await clock.waitForSleeps()
        XCTAssertEqual(device.calls, [gaze])

        device.forget(gaze)
        clock.advance(by: UlanziBridge.retryDelay)
        await ends(bridge.retrying, "the retry never ended")

        XCTAssertEqual(device.calls, [gaze, read, gaze, summon])
        XCTAssertEqual(device.gaze, "repos")
        XCTAssertEqual(bridge.status, .ready)
        XCTAssertEqual(session.phase, .listening)
    }

    /// Once, and no more: a clock still silent after the retry is left alone
    /// until Claudio moves again.
    func testTheRetryIsMadeOnce() async {
        await startedOnAReadyDevice()
        device.isUnplugged = true
        let session = dictating()
        bridge.dictationSessionChanged(session)
        await settle()
        await clock.waitForSleeps()

        clock.advance(by: UlanziBridge.retryDelay)
        await ends(bridge.retrying, "the retry never ended")
        await turns()

        XCTAssertEqual(device.calls, [gaze, read])
        XCTAssertEqual(clock.pendingSleeps, 0, "no second retry")
        XCTAssertEqual(session.phase, .listening)
    }

    /// A newer gaze replaces the retry: the clock hears where Claudio is now,
    /// not where he was.
    func testANewerGazeCancelsTheRetry() async {
        await startedOnAReadyDevice()
        device.answer(gaze, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        let session = dictating()
        bridge.dictationSessionChanged(session)
        await settle()
        await clock.waitForSleeps()
        device.forget(gaze)
        device.clearRequests()

        session.phase = .cleaning
        await settle()
        clock.advance(by: UlanziBridge.retryDelay)
        await settle()

        XCTAssertEqual(device.calls, [read, gaze, summon])
        XCTAssertEqual(gazesSent, ["veille"])
        XCTAssertEqual(clock.pendingSleeps, 0)
    }

    /// Switched off, the bridge takes its retry with it.
    func testStoppingCancelsTheRetry() async {
        await startedOnAReadyDevice()
        device.answer(gaze, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        bridge.dictationSessionChanged(dictating())
        await settle()
        await clock.waitForSleeps()

        bridge.stop()
        await settle()
        device.clearRequests()
        clock.advance(by: UlanziBridge.retryDelay)
        await settle()

        XCTAssertEqual(device.calls, [])
        XCTAssertEqual(clock.pendingSleeps, 0)
    }

    // MARK: - Going off

    /// Switched off mid-dictation, the bridge puts the face away on its way
    /// out, and Settings reads off.
    func testStoppingPutsTheFaceAway() async {
        _ = await startedWithAFaceUp()

        bridge.stop()
        XCTAssertEqual(bridge.status, .off)
        await settle()

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(device.gaze, "off")
    }

    /// Off is off: whatever Claudio does next reaches no device.
    func testAStoppedBridgeSendsNothing() async {
        await startedOnAReadyDevice()
        bridge.stop()
        await settle()
        device.clearRequests()

        bridge.dictationSessionChanged(dictating())
        bridge.correctionSessionChanged(CorrectionSession(request: ClaudioAction.correct.request))
        await settle()

        XCTAssertEqual(device.calls, [])
    }

    /// A bridge that follows another on the same clock, the face unticked
    /// and ticked again, sends nothing until the other's last call, its
    /// off, is done: the face it puts up is never put away behind its back.
    func testABridgeFollowingAnotherWaitsForItsLastCall() async {
        await startedOnAReadyDevice()
        device.holdAnswers()
        bridge.stop()
        await device.waitUntilReceived(1)
        let next = UlanziBridge(client: { [unowned self] in UlanziClient(baseURL: $0, transport: device.transport) },
                                sleep: { [clock] in try await clock.sleep(for: $0) })

        next.start(address: address, after: [bridge.sending].compactMap { $0 })
        await drain()
        XCTAssertEqual(device.calls, [gaze], "nothing from the next bridge while the off is on its way")

        device.releaseAnswers()
        await next.sending?.value
        XCTAssertEqual(device.calls, [gaze, read, gaze])
        XCTAssertEqual(next.status, .ready)
    }

    /// A bridge never started has nothing to stop, nobody to call, and
    /// nothing to put away before the app quits.
    func testABridgeNeverStartedIsOffAndSilent() async {
        bridge.stop()
        bridge.test()
        bridge.prepareToQuit(within: 5)
        await settle()

        XCTAssertEqual(bridge.status, .off)
        XCTAssertFalse(bridge.faceMayBeUp)
        XCTAssertEqual(device.calls, [])
    }

    // MARK: - Quitting

    /// The face may be up while Claudio works, and is not once the clock
    /// has confirmed it away: that is when quitting has nothing to put away.
    func testTheFaceMayBeUpWhileClaudioWorks() async {
        await startedOnAReadyDevice()
        XCTAssertFalse(bridge.faceMayBeUp)

        bridge.dictationSessionChanged(dictating())
        XCTAssertFalse(bridge.faceMayBeUp, "nothing asked of the clock yet")
        await settle()
        XCTAssertTrue(bridge.faceMayBeUp)

        bridge.dictationSessionChanged(nil)
        await settle()
        XCTAssertFalse(bridge.faceMayBeUp)
    }

    /// An off on its way is not an off confirmed: until the clock answers,
    /// the face may still be there.
    func testAnOffOnItsWayLeavesTheFaceInDoubt() async {
        _ = await startedWithAFaceUp()
        device.holdAnswers()

        bridge.dictationSessionChanged(nil)
        await device.waitUntilReceived(1)
        XCTAssertTrue(bridge.faceMayBeUp)

        device.releaseAnswers()
        await settle()
        XCTAssertFalse(bridge.faceMayBeUp)
    }

    /// An off the clock refused leaves the face in doubt: quitting puts it
    /// away all the same, rather than count on a retry that would come with
    /// the app gone.
    func testAFaceInDoubtIsPutAwayAtQuit() async {
        _ = await startedWithAFaceUp()
        device.answer(gaze, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        bridge.dictationSessionChanged(nil)
        await settle()
        XCTAssertTrue(bridge.faceMayBeUp, "the off was refused")

        device.forget(gaze)
        device.clearRequests()
        bridge.prepareToQuit(within: 5)
        await turns()

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(device.gaze, "off")
        XCTAssertEqual(clock.pendingSleeps, 0, "the retry went with the bridge")
    }

    /// Quitting with the face up: it goes before the app does, and the
    /// bridge follows nothing more. The main actor is held all along, as it
    /// is when the updater quits from one of its tasks: the off goes, and
    /// is answered, without it.
    func testQuittingPutsTheFaceAwayFirst() async {
        _ = await startedWithAFaceUp()

        bridge.prepareToQuit(within: 5)

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(device.gaze, "off")
        XCTAssertEqual(bridge.status, .off)
        XCTAssertFalse(bridge.faceMayBeUp)
    }

    /// The face already away, the app goes at once: nothing is sent, and
    /// nothing follows.
    func testQuittingWithTheFaceAwaySendsNothing() async {
        await startedOnAReadyDevice()

        bridge.prepareToQuit(within: 5)
        bridge.dictationSessionChanged(dictating())
        await settle()

        XCTAssertEqual(device.calls, [])
        XCTAssertEqual(bridge.status, .off)
    }

    /// A clock that doesn't answer doesn't hold the app back: the quit goes
    /// on at the bound, the off still unanswered.
    func testQuittingWaitsNoLongerThanTheBound() async {
        _ = await startedWithAFaceUp()
        device.holdAnswers()

        bridge.prepareToQuit(within: 0.05)
        await device.waitUntilReceived(1)

        XCTAssertEqual(device.calls, [gaze])
        XCTAssertEqual(device.gaze, "repos", "the off was never answered")
        device.releaseAnswers()
    }

    // MARK: - The Settings button

    /// "Test": Claudio smiles, then the clock gets its screen back.
    func testTheTestSmilesThenGivesTheScreenBack() async {
        await startedOnAReadyDevice()

        bridge.test()
        await clock.waitForSleeps()
        XCTAssertEqual(gazesSent, ["fait"])
        clock.advance(by: UlanziBridge.testHold)
        await ends(bridge.testing, "the test never ended")

        XCTAssertEqual(device.calls, [gaze, summon, gaze])
        XCTAssertEqual(gazesSent, ["fait", "off"])
    }

    /// Pressed mid-dictation, the test hands the dictation its face back
    /// rather than leaving the clock blank under a microphone still open.
    func testTheTestGivesADictationItsFaceBack() async {
        _ = await startedWithAFaceUp()

        bridge.test()
        await clock.waitForSleeps()
        clock.advance(by: UlanziBridge.testHold)
        await ends(bridge.testing, "the test never ended")

        XCTAssertEqual(gazesSent, ["fait", "repos"])
        XCTAssertFalse(device.calls.contains(summon), "the face never left the screen")
    }

    /// Claudio starting work during the smile takes the screen at once, and
    /// the end of the test leaves it to him.
    func testWorkStartingDuringTheTestKeepsTheScreen() async {
        await startedOnAReadyDevice()

        bridge.test()
        await clock.waitForSleeps()
        bridge.dictationSessionChanged(dictating())
        await settle()
        clock.advance(by: UlanziBridge.testHold)
        await ends(bridge.testing, "the test never ended")

        XCTAssertEqual(gazesSent, ["fait", "repos"])
        XCTAssertEqual(device.gaze, "repos")
    }
}
