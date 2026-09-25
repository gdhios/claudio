import AppKit
@testable import Claudio

/// Galette as a test has it: installed or not, as the test says, and every
/// link a button handed it noted rather than opened. Nothing here asks the
/// Mac which apps it has, nor opens anything.
@MainActor
final class FakeGalette {
    /// What every lookup finds: `nil` is Galette missing.
    let app: GaletteApp?
    /// How many times Galette was looked for: zero proves it never was.
    private(set) var lookups = 0
    /// Every link handed to Galette, in order.
    private(set) var opened: [URL] = []

    init(installed: Bool, browsers: Set<String> = []) {
        app = installed ? GaletteApp(icon: NSImage(), browsers: browsers) : nil
    }

    var service: GaletteService {
        GaletteService(
            find: { [self] in
                lookups += 1
                return app
            },
            open: { [self] url in opened.append(url) }
        )
    }
}
