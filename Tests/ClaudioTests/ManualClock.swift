import XCTest

/// Time as a test runs it. A sleep ends when the test moves the clock past
/// its end, never on the wall clock; a cancelled one ends at once, the way
/// `Task.sleep` does. What a test hands the code under test in place of
/// `Task.sleep(for:)`.
///
/// The wall clock only bounds a wait for sleeps that never begin: code that
/// never gets there fails its test instead of hanging the suite.
@MainActor
final class ManualClock {
    private struct Sleeper {
        let id: Int
        let end: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var now: Duration = .zero
    private var sleepers: [Sleeper] = []
    private var lastID = 0
    private var waiters: [(id: Int, count: Int, continuation: CheckedContinuation<Bool, Never>)] = []

    /// The sleeps begun and not over yet.
    var pendingSleeps: Int { sleepers.count }

    func sleep(for duration: Duration) async throws {
        lastID += 1
        let id = lastID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(Sleeper(id: id, end: now + duration, continuation: continuation))
                wakeWaiters()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Moves the clock on, and ends every sleep due by then, the earliest
    /// first.
    func advance(by duration: Duration) {
        now += duration
        let due = sleepers.filter { $0.end <= now }.sorted { $0.end < $1.end }
        sleepers.removeAll { $0.end <= now }
        due.forEach { $0.continuation.resume() }
    }

    /// Returns once `count` sleeps are under way: the code under test has
    /// reached the point where it waits. Past two seconds it never will, and
    /// the test fails.
    func waitForSleeps(_ count: Int = 1, file: StaticString = #filePath, line: UInt = #line) async {
        guard sleepers.count < count else { return }
        lastID += 1
        let id = lastID
        let ceiling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.release(waiter: id, reached: false)
        }
        let reached = await withCheckedContinuation { waiters.append((id, count, $0)) }
        ceiling.cancel()
        if !reached {
            XCTFail("\(count) sleep(s) awaited, \(sleepers.count) begun", file: file, line: line)
        }
    }

    private func cancel(_ id: Int) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func wakeWaiters() {
        let ready = waiters.filter { sleepers.count >= $0.count }
        waiters.removeAll { sleepers.count >= $0.count }
        ready.forEach { $0.continuation.resume(returning: true) }
    }

    private func release(waiter id: Int, reached: Bool) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: reached)
    }
}
