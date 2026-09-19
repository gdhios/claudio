import Foundation

/// A `claudio://` link, read as a value. One kind so far: a tab of Settings,
/// which is how the plugin — and its download page — send someone to the
/// switch rather than describing where it hides.
///
/// A value, and no window: what a link means is decided here, where it can
/// be proved, and the app does the opening. Anything it doesn't understand is
/// nothing: a link from a later version must not open a window at random.
enum ClaudioURL: Equatable {
    case settings(SettingsSection)

    /// `claudio://settings/<section>`, the section matched whatever its case
    /// against the names Settings stores. `claudio://settings` alone opens
    /// the tab Settings always opens on. Anything else: nil.
    static func parse(_ url: URL) -> ClaudioURL? {
        guard url.scheme?.lowercased() == "claudio" else { return nil }
        guard url.host()?.lowercased() == "settings" else { return nil }

        let name = url.pathComponents.first { $0 != "/" }
        guard let name else { return .settings(.general) }
        guard url.pathComponents.filter({ $0 != "/" }).count == 1 else { return nil }
        let wanted = name.lowercased()
        guard let section = SettingsSection.allCases.first(where: {
            $0.rawValue.lowercased() == wanted
        }) else { return nil }
        return .settings(section)
    }
}
