import Foundation

/// How a coordinator test waits on the coordinator's tasks.
@MainActor
protocol AsyncWaiting {}

extension AsyncWaiting {
    /// Lets the coordinator's tasks run. Everything is on the main actor and
    /// nothing waits on the outside world, so a few turns are enough; the
    /// ceiling only keeps a broken cycle from hanging the suite.
    func settle(until reached: () -> Bool) async {
        var turns = 0
        while !reached(), turns < 500 {
            await Task.yield()
            turns += 1
        }
    }

    /// Waits for something a timer decides rather than a turn of the loop: a
    /// panel closing itself is the only thing that takes real time. The
    /// ceiling keeps a panel that never closes from hanging the suite.
    func wait(seconds: TimeInterval = 2, until reached: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !reached(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
