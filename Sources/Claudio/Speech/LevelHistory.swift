/// The last loudness readings, oldest first, each kept between 0 and 1:
/// the waveform draws one bar per reading and slides as new ones arrive.
/// A value, so the coordinator replaces it and the tests read it.
struct LevelHistory: Equatable, Sendable {
    private(set) var values: [Float]

    /// Starts flat: a panel that has heard nothing yet draws a line of dots.
    init(count: Int = 32) {
        values = Array(repeating: 0, count: max(count, 1))
    }

    func adding(_ level: Float) -> LevelHistory {
        var next = self
        next.values.removeFirst()
        next.values.append(min(max(level, 0), 1))
        return next
    }
}
