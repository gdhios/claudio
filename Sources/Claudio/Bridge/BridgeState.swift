import Foundation

/// What Claudio is doing right now, small enough to fit on a key. The Stream
/// Deck plugin draws a face from it, so the bridge sends this whole value
/// whenever anything in it moves — never a diff, never an event.
///
/// A pure reading of the two sessions: it derives, it never decides. The
/// dictation wins when both exist, because that one has a microphone open.
struct BridgeState: Equatable, Codable {
    enum Activity: String, Codable { case idle, correction, dictation }

    /// The mascot's own gaze, so the key's face and the menu bar's face are
    /// the same face.
    var gaze: ClaudioMascot.Gaze
    var activity: Activity
    /// The session's phase, by its bare case name. `nil` when nothing runs.
    var phase: String?
    /// What the panel says while it works, in the app's language. `nil`
    /// outside the phases that work.
    var label: String?
    /// A dictation locked by a tap: nothing is held, and the next press is
    /// what finishes it.
    var locked: Bool

    /// Claudio waiting: no panel, no microphone.
    static let idle = BridgeState(gaze: .resting, activity: .idle,
                                  phase: nil, label: nil, locked: false)

    @MainActor
    init(correction: CorrectionSession?, dictation: DictationSession?) {
        if let dictation {
            let phase = dictation.phase
            self.init(gaze: ClaudioMascot.Gaze(phase),
                      activity: .dictation,
                      phase: phase.bridgeName,
                      // Only the two phases a model or a paste is working
                      // through have something to announce.
                      label: phase == .cleaning || phase == .pasting
                          ? dictation.output.progressLabel : nil,
                      locked: dictation.isLocked)
        } else if let correction {
            let phase = correction.phase
            self.init(gaze: ClaudioMascot.Gaze(phase),
                      activity: .correction,
                      phase: phase.bridgeName,
                      label: phase == .streaming ? correction.progressLabel : nil,
                      locked: false)
        } else {
            self = .idle
        }
    }

    init(gaze: ClaudioMascot.Gaze, activity: Activity,
         phase: String?, label: String?, locked: Bool) {
        self.gaze = gaze
        self.activity = activity
        self.phase = phase
        self.label = label
        self.locked = locked
    }

    /// `phase` and `label` go out as JSON `null` rather than disappearing:
    /// the plugin reads the keys, and a missing one would look like a frame
    /// from another version.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gaze, forKey: .gaze)
        try container.encode(activity, forKey: .activity)
        if let phase { try container.encode(phase, forKey: .phase) }
        else { try container.encodeNil(forKey: .phase) }
        if let label { try container.encode(label, forKey: .label) }
        else { try container.encodeNil(forKey: .label) }
        try container.encode(locked, forKey: .locked)
    }
}

// MARK: - Phase names on the wire

/// The bare case name, which is what the plugin switches on. A phase
/// carrying a message sends its name alone: the sentence belongs to the
/// panel, where there is room to read it.
extension CorrectionSession.Phase {
    var bridgeName: String {
        switch self {
        case .capturing: "capturing"
        case .choosingAction: "choosingAction"
        case .askingInstruction: "askingInstruction"
        case .listeningInstruction: "listeningInstruction"
        case .instructionNotHeard: "instructionNotHeard"
        case .streaming: "streaming"
        case .done: "done"
        case .noSelection: "noSelection"
        case .missingKey: "missingKey"
        case .error: "error"
        }
    }
}

extension DictationSession.Phase {
    var bridgeName: String {
        switch self {
        case .listening: "listening"
        case .finishing: "finishing"
        case .cleaning: "cleaning"
        case .pasting: "pasting"
        case .done: "done"
        case .empty: "empty"
        case .error: "error"
        }
    }
}
