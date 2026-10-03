import Foundation

/// A `claudio://` link, read as a value. Two kinds: a tab of Settings,
/// which is how the plugin — and its download page — send someone to the
/// switch rather than describing where it hides; and a music subject,
/// which is how Galette's "Tell me more" hands an album or an artist to
/// Claude through Claudio's panel.
///
/// A value, and no window: what a link means is decided here, where it can
/// be proved, and the app does the opening. Anything it doesn't understand is
/// nothing: a link from a later version must not open a window at random.
enum ClaudioURL: Equatable {
    case settings(SettingsSection)
    case music(MusicSubject)

    /// `claudio://settings/<section>`, the section matched whatever its case
    /// against the names Settings stores. `claudio://settings` alone opens
    /// the tab Settings always opens on. `claudio://music?kind=…&artist=…`
    /// is a subject. Anything else: nil.
    static func parse(_ url: URL) -> ClaudioURL? {
        guard url.scheme?.lowercased() == "claudio" else { return nil }
        if url.host()?.lowercased() == "music" { return music(url).map(ClaudioURL.music) }
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

    /// `kind` (album or artist) and `artist` are required, `title` too for
    /// an album; `mbid`, `date`, `type`, `label` and `country` are the facts
    /// Galette has. Half a subject is no subject.
    private static func music(_ url: URL) -> MusicSubject? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return raw
        }
        guard let kind = value("kind").flatMap(MusicSubject.Kind.init(rawValue:)),
              let artist = value("artist") else { return nil }
        let title = value("title")
        // A link names an album or an artist; the track is the card's own.
        if kind == .track || (kind == .album && title == nil) { return nil }
        return MusicSubject(kind: kind, artist: artist, title: kind == .album ? title : nil,
                            mbid: value("mbid"), firstReleaseDate: value("date"), type: value("type"),
                            label: value("label"), country: value("country"))
    }
}
