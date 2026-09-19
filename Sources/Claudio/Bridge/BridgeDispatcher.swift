import Foundation

/// Where a frame becomes a gesture. Pure routing: the dispatcher holds no
/// coordinator, only the closures that reach them, so every key of the plugin
/// is proved without a panel, a microphone or a window in the way.
@MainActor
struct BridgeDispatcher {
    var triggerAction: (ClaudioAction) -> Void
    var triggerFree: () -> Void
    var triggerPalette: () -> Void
    /// The press carries what it dictates — the shortcut slot and what the
    /// words become — as a keyboard shortcut does.
    var dictationDown: (BridgeDictationLanguage, DictationOutput) -> Void
    var dictationUp: () -> Void
    var dictationCancel: () -> Void
    var applyLayout: (WindowLayout) -> Void
    var nextScreen: () -> Void
    var openSettings: () -> Void

    /// Routes one command. `hello` is not a command: the server answers it
    /// itself, so this returns `false` for it, and for anything else the
    /// server is the one to handle.
    func dispatch(_ message: BridgeInbound) -> Bool {
        switch message {
        case .hello:
            return false
        case .action(.catalog(let action)):
            triggerAction(action)
        case .action(.free):
            triggerFree()
        case .action(.palette):
            triggerPalette()
        case .dictationDown(let language, let output):
            dictationDown(language, output)
        case .dictationUp:
            dictationUp()
        case .dictationCancel:
            dictationCancel()
        case .window(.layout(let layout)):
            applyLayout(layout)
        case .window(.nextScreen):
            nextScreen()
        case .openSettings:
            openSettings()
        }
        return true
    }
}
