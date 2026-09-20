import Foundation

/// What the Stream Deck tab shows, and the switch it offers. One object the
/// app fills in and the tab reads: the bridge's status as it changes, whether
/// the plugin is in its folder, and the choice stored for it — `nil` while
/// nobody has chosen, which is when the plugin's presence decides.
///
/// It stores nothing and opens nothing itself. The app hands it `applyChoice`,
/// which writes the choice down and starts or stops the bridge, and `refresh`,
/// which re-reads both when the tab opens. A preview sets neither: it fills
/// the fields by hand and shows a screen that is the same on every machine.
@MainActor
final class StreamDeckStatusModel: ObservableObject {
    /// The one the tab reads. The app feeds it; a preview overwrites it.
    static let shared = StreamDeckStatusModel()

    @Published var status: StreamDeckBridge.Status = .off
    @Published var pluginInstalled = false
    /// nil = automatic: no choice was made, and the plugin decides.
    @Published var choice: Bool?

    /// Called with the new choice — `nil` for back to automatic. The app
    /// stores it and switches the bridge to match.
    var applyChoice: ((Bool?) -> Void)?
    /// Called when the tab opens: the plugin may have been installed, or
    /// removed, since the last look.
    var refresh: (() -> Void)?

    /// Nobody chose: the switch shows what the plugin decided.
    var isAutomatic: Bool { choice == nil }

    /// Where the switch sits: the choice if there is one, the plugin's
    /// presence otherwise.
    var isOn: Bool { choice ?? pluginInstalled }

    /// Flipping the switch is a choice, and a choice outranks the plugin in
    /// both directions: no socket for whoever said no, a socket for whoever
    /// keeps their plugin somewhere Claudio can't see.
    func setOn(_ on: Bool) {
        choice = on
        applyChoice?(on)
    }

    /// Hands the decision back to the plugin's presence.
    func backToAutomatic() {
        choice = nil
        applyChoice?(nil)
    }
}
