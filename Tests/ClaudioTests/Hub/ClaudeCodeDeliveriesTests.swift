import XCTest
@testable import Claudio

/// The board's commands on their way to several clocks. Each waits for
/// every clock it went to; once all have answered it is done, and the done
/// ones come back in the order they were sent, whatever the order of the
/// answers. A clock let go answers nothing more, and no command waits for
/// it.
final class ClaudeCodeDeliveriesTests: XCTestCase {

    private let desk = UUID()
    private let lounge = UUID()
    private let hold = UlanziCommand.notify(UlanziNotification(name: "cc-5f0c2a9e", text: "BAGUETTE DÉCISION"))
    private let dismissal = UlanziCommand.dismiss(name: "cc-5f0c2a9e")
    private let indicatorOff = UlanziCommand.indicator(nil)

    private func outcome(_ command: UlanziCommand, taken: Bool, missed: Bool) -> ClaudeCodeDeliveries.Outcome {
        ClaudeCodeDeliveries.Outcome(command: command, taken: taken, missed: missed)
    }

    /// One clock: done at its answer.
    func testOneClockAnswersForItself() {
        var deliveries = ClaudeCodeDeliveries()
        let number = deliveries.send(hold, to: [desk])

        XCTAssertEqual(deliveries.answer(number, from: desk, taken: true),
                       [outcome(hold, taken: true, missed: false)])
    }

    /// Two clocks: nothing until both have answered; taken when one took
    /// it, missed when one missed it.
    func testACommandWaitsForEveryClock() {
        var deliveries = ClaudeCodeDeliveries()
        let number = deliveries.send(hold, to: [desk, lounge])

        XCTAssertEqual(deliveries.answer(number, from: desk, taken: false), [])
        XCTAssertEqual(deliveries.answer(number, from: lounge, taken: true),
                       [outcome(hold, taken: true, missed: true)])
    }

    /// Both missed it: not taken.
    func testACommandEveryClockMissedIsNotTaken() {
        var deliveries = ClaudeCodeDeliveries()
        let number = deliveries.send(dismissal, to: [desk, lounge])

        _ = deliveries.answer(number, from: lounge, taken: false)
        XCTAssertEqual(deliveries.answer(number, from: desk, taken: false),
                       [outcome(dismissal, taken: false, missed: true)])
    }

    /// The done ones come back in the order sent: a later command done
    /// first waits for the one before it.
    func testTheDoneOnesComeBackInTheOrderSent() {
        var deliveries = ClaudeCodeDeliveries()
        let first = deliveries.send(dismissal, to: [desk, lounge])
        let second = deliveries.send(hold, to: [lounge])

        XCTAssertEqual(deliveries.answer(first, from: lounge, taken: true), [])
        XCTAssertEqual(deliveries.answer(second, from: lounge, taken: true), [])
        XCTAssertEqual(deliveries.answer(first, from: desk, taken: true),
                       [outcome(dismissal, taken: true, missed: false),
                        outcome(hold, taken: true, missed: false)])
    }

    /// A clock let go: what waited for it alone is done, with what the
    /// others made of it; a command no clock answered is neither taken nor
    /// missed.
    func testAClockLetGoIsWaitedForNoMore() {
        var deliveries = ClaudeCodeDeliveries()
        let first = deliveries.send(hold, to: [desk, lounge])
        _ = deliveries.send(indicatorOff, to: [desk])
        _ = deliveries.answer(first, from: lounge, taken: true)

        XCTAssertEqual(deliveries.forget(desk),
                       [outcome(hold, taken: true, missed: false),
                        outcome(indicatorOff, taken: false, missed: false)])
    }

    /// An answer twice, or from a clock the command never went to, changes
    /// nothing.
    func testAnAnswerFromNobodyChangesNothing() {
        var deliveries = ClaudeCodeDeliveries()
        let number = deliveries.send(hold, to: [desk, lounge])

        XCTAssertEqual(deliveries.answer(number, from: UUID(), taken: true), [])
        XCTAssertEqual(deliveries.answer(number, from: desk, taken: false), [])
        XCTAssertEqual(deliveries.answer(number, from: desk, taken: true), [])
        XCTAssertEqual(deliveries.answer(number, from: lounge, taken: false),
                       [outcome(hold, taken: false, missed: true)])
        XCTAssertEqual(deliveries.answer(number, from: lounge, taken: true), [])
    }
}
