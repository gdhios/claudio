/// What the Claude Code hub asks of the Ulanzi, as values: the board decides
/// them, the hub sends them in order, and a test reads them as a list.
enum UlanziCommand: Equatable {
    /// A notification on the screen, passing or held.
    case notify(UlanziNotification)
    /// The held notification of that name taken away. Already gone is fine.
    case dismiss(name: String)
    /// Indicator 1 lit as described, or switched off for nil.
    case indicator(UlanziIndicator?)
}

/// A notification as AWTRIX NG takes it on `POST /api/v1/notifications`.
/// Only the keys set are sent.
struct UlanziNotification: Equatable {
    /// Names a held notification, so it can be dismissed. A new one under a
    /// name already held replaces it.
    var name: String? = nil
    var text: String
    var textColor: String? = nil
    var durationMs: Int? = nil
    /// Stays on screen until dismissed, masking every app, the face included.
    var hold: Bool? = nil
    /// Lights a screen that was off.
    var wakeup: Bool? = nil
    var textBlinkMs: Int? = nil
    var soundRtttl: String? = nil
}

/// Indicator 1 lit: a colour that blinks, or breathes, or both.
struct UlanziIndicator: Equatable {
    var color: String
    var blinkMs: Int
    var fadeMs: Int
}
