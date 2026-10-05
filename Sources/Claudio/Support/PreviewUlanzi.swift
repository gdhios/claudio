import Foundation

/// The Ulanzi tab as the previews show it, set by hand: nothing is read
/// from this Mac's preferences or Claude Code's settings, no device is
/// called and no socket opened. With no app behind the model, the buttons
/// do nothing.
@MainActor
enum PreviewUlanzi {
    /// `settings-ulanzi`: the desk ready on both roles; the lounge's face
    /// out of reach and its flags waiting; the relay listening, the hook
    /// installed. `settings-ulanzi-vide`: no clock, the relay off, no hook.
    static func fill(_ model: UlanziStatusModel, empty: Bool) {
        guard !empty else {
            model.show([])
            model.hub = .off
            model.hook = .absent
            return
        }
        let desk = UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!)
        let lounge = UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!)
        model.show([desk, lounge])
        model.faceStatusChanged(.ready, of: desk.id)
        model.alertsStatusChanged(.ready, of: desk.id)
        let timeout = loc("La requête a expiré.", en: "The request timed out.")
        model.faceStatusChanged(.failed(.unreachable(timeout)), of: lounge.id)
        model.alertsStatusChanged(.pending, of: lounge.id)
        model.hub = .listening(port: 50678)
        model.hook = .installed
    }
}
