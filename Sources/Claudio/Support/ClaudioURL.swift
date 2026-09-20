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

        // The root counts as a path component of its own: what is named
        // after the host is what is left once it is dropped.
        let parts = url.pathComponents.filter { $0 != "/" }
        switch parts.count {
        case 0:
            return .settings(.general)
        case 1:
            let wanted = parts[0].lowercased()
            guard let section = SettingsSection.allCases.first(where: {
                $0.rawValue.lowercased() == wanted
            }) else { return nil }
            return .settings(section)
        default:
            // A link half understood is a link not understood.
            return nil
        }
    }
}
