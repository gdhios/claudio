import XCTest
@testable import Claudio

/// A panel that asks nothing of anyone shouldn't have to be waved away: a
/// shortcut fired on an empty selection used to leave "No selection found"
/// sitting in the middle of the screen until someone pressed Esc. Which
/// phases take themselves off, and after how long, is held here — the delay
/// comes from the dictation's own message durations, so the two kinds of
/// panel keep the same sense of time.
@MainActor
final class PanelAutoDismissTests: XCTestCase {

    private let durations = DictationCoordinator.MessageDurations.standard

    /// The case the change exists for. Same duration as "Nothing heard":
    /// both are a glance, not a decision.
    func testNoSelectionTakesItselfOffTheScreen() {
        XCTAssertEqual(CorrectionSession.Phase.noSelection.autoDismissDelay(durations),
                       durations.empty)
    }

    /// Everything the user still has something to do with stays put: a result
    /// to paste, a key to add, an error to read, a stream under way, a row to
    /// pick, an instruction to type.
    func testThePhasesThatWaitForTheUserStay() {
        let waiting: [CorrectionSession.Phase] = [
            .capturing, .choosingAction, .askingInstruction, .listeningInstruction,
            .streaming, .done, .missingKey, .error("the API said no"),
        ]
        for phase in waiting {
            XCTAssertNil(phase.autoDismissDelay(durations), "\(phase) should wait for the user")
        }
    }

    /// "Nothing heard" closes itself too, but the coordinator that opened the
    /// microphone owns that ending: it picks between a silence and a failure,
    /// which this table can't see. Answering here would close the panel twice.
    func testAnUnheardInstructionIsLeftToTheCoordinatorThatListened() {
        XCTAssertNil(CorrectionSession.Phase.instructionNotHeard(reason: nil)
            .autoDismissDelay(durations))
    }
}
