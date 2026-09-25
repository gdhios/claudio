import AppKit

/// Galette as a panel found it when it opened: its icon, shown before the
/// buttons, and this Mac's browsers — whose tracks are a video's title and a
/// channel rather than an artist and an album.
struct GaletteApp {
    let icon: NSImage
    /// Bundle ids of the apps that open `https://` links.
    let browsers: Set<String>

    /// This track's buttons, in order: none when it gives nothing to open.
    func links(for track: NowPlayingTrack) -> [GaletteLink] {
        let playerIsBrowser = track.bundleID.map(browsers.contains) ?? false
        return GaletteLink.links(for: track, playerIsBrowser: playerIsBrowser)
    }
}

/// All the Galette buttons ask of the Mac: whether Galette is on it, and to
/// hand it a link. Injected like `PasteService`: a test says whether it is
/// installed and notes what it was handed, and nothing in a test or a preview
/// asks this machine.
@MainActor
struct GaletteService {
    /// Galette when an app on this Mac opens `galette://` links, `nil` when
    /// none does — and then no button shows, nor anything saying why. Asked
    /// as each panel opens: installed or removed since, the next one knows.
    var find: @MainActor () -> GaletteApp?
    /// Hands a link to Galette, which comes forward on it.
    var open: @MainActor (URL) -> Void

    static let system = GaletteService(
        find: {
            let workspace = NSWorkspace.shared
            guard let app = workspace.urlForApplication(toOpen: probe) else { return nil }
            let browsers = workspace.urlsForApplications(toOpen: URL(string: "https://example.com")!)
                .compactMap { Bundle(url: $0)?.bundleIdentifier }
            return GaletteApp(icon: workspace.icon(forFile: app.path), browsers: Set(browsers))
        },
        open: { NSWorkspace.shared.open($0) }
    )

    /// Any link Galette reads: what matters is which app would open it.
    private static let probe = URL(string: "galette://artist?name=x")!
}
