import XCTest

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

    /// Waits for a coordinator's task to end. One that never does (a cycle
    /// nothing finishes, a stream still open) fails its test with `failure`
    /// instead of hanging the suite: past the ceiling it is cancelled.
    func ends(_ task: Task<Void, Never>?, within seconds: TimeInterval = 2, _ failure: String,
              file: StaticString = #filePath, line: UInt = #line) async {
        guard let task else { return }
        let ceiling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            XCTFail(failure, file: file, line: line)
            task.cancel()
        }
        await task.value
        ceiling.cancel()
    }
}
