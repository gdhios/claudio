import Foundation

/// What the Ulanzi tab shows, and the two things it asks for: a new address,
/// and a test. One object the app fills in and the tab reads, like
/// `StreamDeckStatusModel`: the bridge's status as it changes, and the
/// address as it is kept.
///
/// It stores nothing and calls nothing itself. The app hands it
/// `applyAddress`, which writes the address down and restarts the bridge on
/// it, and `test`. A preview sets neither: it fills the fields by hand and
/// shows a screen that is the same on every machine.
@MainActor
final class UlanziStatusModel: ObservableObject {
    /// The one the tab reads. The app feeds it; a preview overwrites it.
    static let shared = UlanziStatusModel()

    @Published var status: UlanziBridge.Status = .off
    /// The address kept, written the way it is called; empty when none is.
    @Published var address = ""

    /// Called with the address submitted, nil for none. The app stores it
    /// and restarts the bridge on it.
    var applyAddress: ((URL?) -> Void)?
    /// Called by the Test button: Claudio smiles on the clock for a moment.
    var test: (() -> Void)?

    /// The address field, submitted. Blank switches the face off; an address
    /// that can be called is applied, and kept the way it will be called;
    /// anything else leaves the kept one alone, and says so with `false`.
    /// The address already kept is applied again to nobody: the bridge would
    /// install, put the face away and start over for nothing.
    @discardableResult
    func submit(_ typed: String) -> Bool {
        let url: URL?
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = nil
        } else {
            guard let readable = AppSettings.normalizedUlanziURL(typed) else { return false }
            url = readable
        }
        let kept = url?.absoluteString ?? ""
        guard kept != address else { return true }
        address = kept
        applyAddress?(url)
        return true
    }

    /// The Test button: the address typed is kept first, then tried. One
    /// nobody could call tries nothing, and says so with `false`: the old
    /// one smiling would say the typo works.
    @discardableResult
    func testTyped(_ typed: String) -> Bool {
        guard submit(typed) else { return false }
        if !address.isEmpty { test?() }
        return true
    }

    /// The status, in one line. Out of reach and in error are two things to
    /// fix: a cable or an address, against a clock that answered no, in its
    /// own words.
    var statusLine: String {
        switch status {
        case .off: loc("Désactivé", en: "Off")
        case .installing: loc("Installation du visage…", en: "Installing the face…")
        case .ready: loc("Prêt", en: "Ready")
        case .failed(.unreachable(let reason)): loc("Injoignable : \(reason)", en: "Unreachable: \(reason)")
        case .failed(let failure):
            loc("Erreur : \(failure.localizedDescription)", en: "Error: \(failure.localizedDescription)")
        }
    }
}
