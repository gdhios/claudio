import XCTest
@testable import Claudio

/// What the Stream Deck is told Claudio is doing, derived from the sessions
/// alone. No coordinator, no panel, no network: a session is built by hand,
/// its phase set, and the state read back as a value.
@MainActor
final class BridgeStateTests: XCTestCase {

    /// Every phase a correction goes through. Listed by hand — `Phase` isn't
    /// `CaseIterable` — and kept honest by `bridgeName`'s own exhaustive
    /// switch, which stops compiling when a case is added.
    private let correctionPhases: [CorrectionSession.Phase] = [
        .capturing, .choosingAction, .askingInstruction, .listeningInstruction,
        .instructionNotHeard(reason: nil), .streaming, .done, .noSelection,
        .missingKey, .error("boom"),
    ]

    private let dictationPhases: [DictationSession.Phase] = [
        .listening, .finishing, .cleaning, .pasting, .done, .empty, .error("boom"),
    ]

    private func correction(_ phase: CorrectionSession.Phase,
                            action: ClaudioAction = .correct) -> CorrectionSession {
        let session = CorrectionSession(request: action.request)
        session.phase = phase
        return session
    }

    private func dictation(_ phase: DictationSession.Phase,
                           output: DictationOutput = .cleanup,
                           locked: Bool = false) -> DictationSession {
        let session = DictationSession(language: .frFR, model: .raw, output: output)
        session.phase = phase
        session.isLocked = locked
        return session
    }

    // MARK: - Nothing under way

    func testNothingUnderWayIsTheIdleState() {
        XCTAssertEqual(BridgeState(correction: nil, dictation: nil), .idle)
        XCTAssertEqual(BridgeState.idle,
                       BridgeState(gaze: .repos, activity: .idle,
                                   phase: nil, label: nil, locked: false))
    }

    // MARK: - The gaze

    /// The key's face is the menu bar's face: the bridge reads the gaze
    /// through the mascot rather than deciding it a second time.
    func testEveryCorrectionPhaseCarriesTheMascotsGaze() {
        for phase in correctionPhases {
            let state = BridgeState(correction: correction(phase), dictation: nil)
            XCTAssertEqual(state.gaze, ClaudioMascot.Gaze(phase), "\(phase)")
        }
    }

    func testEveryDictationPhaseCarriesTheMascotsGaze() {
        for phase in dictationPhases {
            let state = BridgeState(correction: nil, dictation: dictation(phase))
            XCTAssertEqual(state.gaze, ClaudioMascot.Gaze(phase), "\(phase)")
        }
    }

    /// The gaze travels as a string: these four are wire values.
    func testGazeRawValuesAreTheWireNames() {
        XCTAssertEqual(ClaudioMascot.Gaze.repos.rawValue, "repos")
        XCTAssertEqual(ClaudioMascot.Gaze.veille.rawValue, "veille")
        XCTAssertEqual(ClaudioMascot.Gaze.fait.rawValue, "fait")
        XCTAssertEqual(ClaudioMascot.Gaze.vide.rawValue, "vide")
    }

    // MARK: - The phase name

    func testCorrectionPhaseNamesAreTheBareCaseNames() {
        let names = correctionPhases.map {
            BridgeState(correction: correction($0), dictation: nil).phase
        }
        XCTAssertEqual(names, ["capturing", "choosingAction", "askingInstruction",
                               "listeningInstruction", "instructionNotHeard", "streaming",
                               "done", "noSelection", "missingKey", "error"])
    }

    func testDictationPhaseNamesAreTheBareCaseNames() {
        let names = dictationPhases.map {
            BridgeState(correction: nil, dictation: dictation($0)).phase
        }
        XCTAssertEqual(names, ["listening", "finishing", "cleaning", "pasting",
                               "done", "empty", "error"])
    }

    /// A phase carrying a message sends its name, never the message: the
    /// plugin shows a face, and the sentence belongs to the panel.
    func testAPhaseWithAMessageSendsItsNameOnly() {
        let failed = BridgeState(correction: correction(.error("le réseau a lâché")),
                                 dictation: nil)
        XCTAssertEqual(failed.phase, "error")
        XCTAssertEqual(failed.label, nil)
    }

    // MARK: - The label

    /// The label is the app's own progress label, so the key says the same
    /// thing as the panel — and in the same language.
    func testAStreamingCorrectionCarriesItsProgressLabel() {
        let state = BridgeState(correction: correction(.streaming, action: .summarize),
                                dictation: nil)
        XCTAssertEqual(state.activity, .correction)
        XCTAssertEqual(state.label, ClaudioAction.summarize.request.progressLabel)
    }

    /// Nothing is being worked on outside the stream: no label to show.
    func testACorrectionCarriesNoLabelOutsideTheStream() {
        for phase in correctionPhases where phase != .streaming {
            let state = BridgeState(correction: correction(phase), dictation: nil)
            XCTAssertNil(state.label, "\(phase)")
        }
    }

    /// A translated dictation says "Translating…", not "Cleaning up…": the
    /// label is the output's own.
    func testAWorkingDictationCarriesItsOutputsProgressLabel() {
        for phase in [DictationSession.Phase.cleaning, .pasting] {
            let state = BridgeState(correction: nil,
                                    dictation: dictation(phase, output: .translateEN))
            XCTAssertEqual(state.activity, .dictation)
            XCTAssertEqual(state.label, DictationOutput.translateEN.progressLabel, "\(phase)")
        }
    }

    func testADictationCarriesNoLabelWhileItListensOrIsOver() {
        for phase in dictationPhases where phase != .cleaning && phase != .pasting {
            let state = BridgeState(correction: nil, dictation: dictation(phase))
            XCTAssertNil(state.label, "\(phase)")
        }
    }

    // MARK: - Locked

    /// A dictation locked by a tap listens with nothing held: the key has to
    /// show it, since the next press is what finishes it.
    func testALockedDictationSaysSo() {
        let locked = BridgeState(correction: nil,
                                 dictation: dictation(.listening, locked: true))
        XCTAssertTrue(locked.locked)
        let held = BridgeState(correction: nil, dictation: dictation(.listening))
        XCTAssertFalse(held.locked)
    }

    /// Only a dictation can be locked; a correction never claims it.
    func testACorrectionIsNeverLocked() {
        XCTAssertFalse(BridgeState(correction: correction(.streaming), dictation: nil).locked)
    }

    // MARK: - Who wins

    /// Both at once — a dictation started while a correction panel was still
    /// up: the dictation is the one with a microphone open, so it wins.
    func testTheDictationWinsOverACorrection() {
        let state = BridgeState(correction: correction(.streaming),
                                dictation: dictation(.listening))
        XCTAssertEqual(state.activity, .dictation)
        XCTAssertEqual(state.phase, "listening")
        XCTAssertNil(state.label)
    }
}
