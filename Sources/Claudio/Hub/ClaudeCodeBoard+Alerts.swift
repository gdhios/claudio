/// What the clock shows and plays, as the Python hook that drove it before
/// Claudio had it.
extension ClaudeCodeBoard {
    /// Short RTTTL tunes, an octave below the shrill top of the TC001's
    /// buzzer, in sixteenths at 140. Picked by ear by Guillaume.
    enum Melody {
        static let done = "fini:d=16,o=5,b=140:c,d,e,f,g,a,b,c6"
        static let decision = "dec:d=16,o=5,b=140:g,p,g,8c6"
        static let blocked = "blk:d=16,o=5,b=140:g,f#,f,8e"
        static let waiting = "att:d=16,o=5,b=140:e,p,e,p,8a"
    }

    static let waitingColor = "#FF851B"
    static let plainColor = "#AAAAAA"
    /// Orange that breathes: a session waits.
    static let waitingIndicator = UlanziIndicator(color: "#FF851B", blinkMs: 0, fadeMs: 2000)
    /// Red that blinks: a session is blocked.
    static let blockedIndicator = UlanziIndicator(color: "#FF2D2D", blinkMs: 600, fadeMs: 0)

    /// The folder's last name, twelve characters at most, in capitals;
    /// CLAUDE without one.
    static func project(of cwd: String?) -> String {
        var path = Substring(cwd ?? "")
        while path.hasSuffix("/") { path = path.dropLast() }
        let last = path.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        return String((last.isEmpty ? "claude" : last).prefix(12)).uppercased()
    }

    /// `cc-` and the session's first eight characters.
    static func alertName(for sessionID: String) -> String {
        "cc-" + sessionID.prefix(8)
    }

    /// What a turn ending under `flag` shows: done and info pass, a decision
    /// and a blocker hold until answered, no flag winks the project's name.
    static func notification(for flag: ClaudeCodeFlag?, project: String, name: String) -> UlanziNotification {
        guard let flag else {
            return UlanziNotification(text: project, textColor: plainColor, durationMs: 1500)
        }
        let text = "\(project) \(flag.word)"
        switch flag {
        case .done:
            return UlanziNotification(text: text, textColor: flag.color, durationMs: 6000, soundRtttl: Melody.done)
        case .info:
            return UlanziNotification(text: text, textColor: flag.color, durationMs: 4000)
        case .decision:
            return UlanziNotification(name: name, text: text, textColor: flag.color,
                                      hold: true, wakeup: true, soundRtttl: Melody.decision)
        case .blocked:
            return UlanziNotification(name: name, text: text, textColor: flag.color,
                                      hold: true, wakeup: true, textBlinkMs: 600, soundRtttl: Melody.blocked)
        }
    }
}

extension ClaudeCodeFlag {
    /// The wait a turn ending under this flag leaves: a decision waits in
    /// orange, a blocker in red, the other two not at all.
    var waitLevel: ClaudeCodeBoard.Level? {
        switch self {
        case .decision: .orange
        case .blocked: .red
        case .done, .info: nil
        }
    }
}
