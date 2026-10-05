import Foundation

/// The board's commands on their way to the clocks, in the order sent. Each
/// went to every recipient then, the hub's links, and waits for all of
/// them: one that took it, one that missed it, or one let go meanwhile,
/// which answers nothing more. Once all have answered it is done, and the
/// done ones go back to the board in the order they were sent, which is the
/// order the board expects them in.
struct ClaudeCodeDeliveries<Recipient: Hashable> {
    /// What the clocks made of one command.
    struct Outcome: Equatable {
        let command: UlanziCommand
        /// At least one clock took it.
        let taken: Bool
        /// At least one clock missed it.
        let missed: Bool
    }

    private struct Entry {
        let number: Int
        let command: UlanziCommand
        var waiting: Set<Recipient>
        var taken = false
        var missed = false
    }

    private var entries: [Entry] = []
    private var sent = 0

    /// `command` sent to `recipients`: the number its answers come under.
    mutating func send(_ command: UlanziCommand, to recipients: [Recipient]) -> Int {
        sent += 1
        entries.append(Entry(number: sent, command: command, waiting: Set(recipients)))
        return sent
    }

    /// `recipient` answered command `number`, taking it or not. Returns the
    /// commands done since, in the order sent.
    mutating func answer(_ number: Int, from recipient: Recipient, taken: Bool) -> [Outcome] {
        guard let index = entries.firstIndex(where: { $0.number == number }),
              entries[index].waiting.remove(recipient) != nil else { return [] }
        if taken {
            entries[index].taken = true
        } else {
            entries[index].missed = true
        }
        return done()
    }

    /// `recipient` is let go: nothing waits for it any more. Returns the
    /// commands done since, in the order sent.
    mutating func forget(_ recipient: Recipient) -> [Outcome] {
        for index in entries.indices {
            entries[index].waiting.remove(recipient)
        }
        return done()
    }

    /// The commands every clock has answered, from the head: one still
    /// waiting holds back those sent after it.
    private mutating func done() -> [Outcome] {
        var outcomes: [Outcome] = []
        while let head = entries.first, head.waiting.isEmpty {
            entries.removeFirst()
            outcomes.append(Outcome(command: head.command, taken: head.taken, missed: head.missed))
        }
        return outcomes
    }
}
