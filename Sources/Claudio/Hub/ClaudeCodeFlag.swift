/// The four squares a Claude Code turn opens with in Guillaume's sessions,
/// each saying what the turn leaves him: done, a decision to make, a
/// blocker, or something to know.
enum ClaudeCodeFlag: CaseIterable {
    case done, decision, blocked, info

    /// The flag of `text`: the first square found in this order, green,
    /// orange, red, blue, whatever comes first in the text, as the Python
    /// hook before Claudio read it. Looked for among the scalars, so a square
    /// followed by a variation selector still counts. nil without one.
    static func `in`(_ text: String?) -> ClaudeCodeFlag? {
        guard let scalars = text?.unicodeScalars else { return nil }
        return allCases.first { scalars.contains($0.square) }
    }

    var square: Unicode.Scalar {
        switch self {
        case .done: "🟩"
        case .decision: "🟧"
        case .blocked: "🟥"
        case .info: "🟦"
        }
    }

    /// What the clock writes after the project's name.
    var word: String {
        switch self {
        case .done: "FINI"
        case .decision: "DÉCISION"
        case .blocked: "BLOCAGE"
        case .info: "INFO"
        }
    }

    /// The square's colour, for the text.
    var color: String {
        switch self {
        case .done: "#2ECC40"
        case .decision: "#FF851B"
        case .blocked: "#FF2D2D"
        case .info: "#3D9BFF"
        }
    }
}
