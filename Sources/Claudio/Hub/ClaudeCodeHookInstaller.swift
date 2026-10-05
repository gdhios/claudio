import Foundation

/// Hooks the relay into Claude Code from Settings, and takes it out again.
/// The relay ships inside the app; installing copies it to a place that
/// doesn't move with the app, then adds its four entries to Claude Code's
/// settings, after keeping the file as it was next to it, the first time.
/// Removing takes the entries out, the same way. Nothing else in the file
/// changes, and a file that can't be read is never written over. At
/// launch, the copy is brought up to the relay the app ships.
///
/// The three paths are injected: a test works in a temporary folder, never
/// on this Mac's settings.
struct ClaudeCodeHookInstaller {
    /// Where the hook stands, for Settings.
    enum HookState: Equatable {
        case installed
        case absent
        /// The settings can't be read: why. Nothing is written over them.
        case unreadable(String)
        /// This version of the app has no relay to install.
        case noRelay
    }

    enum Failure: Error, Equatable {
        case unreadable(String)
        case noRelay
    }

    let settingsURL: URL
    /// The relay as the app ships it, nil when it doesn't.
    let relaySource: URL?
    let relayDestination: URL

    init(settingsURL: URL = ClaudeCodeHookInstaller.defaultSettingsURL,
         relaySource: URL? = ClaudeCodeHookInstaller.bundledRelay,
         relayDestination: URL = ClaudeCodeHookInstaller.defaultRelayDestination) {
        self.settingsURL = settingsURL
        self.relaySource = relaySource
        self.relayDestination = relayDestination
    }

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// In Claudio's Application Support folder, next to the handshake file
    /// the relay reads.
    static var defaultRelayDestination: URL {
        BridgeHandshakeFile.defaultDirectory.appendingPathComponent(relayName)
    }

    /// `Scripts/build_app.sh` puts it in the bundle's resources; a
    /// `swift run` has none.
    static var bundledRelay: URL? {
        Bundle.main.url(forResource: "claudio-claude-code", withExtension: "py")
    }

    /// The settings as they were before Claudio first wrote them, next to
    /// them.
    var backupURL: URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent(settingsURL.lastPathComponent + ".claudio-backup")
    }

    // MARK: - What Settings shows

    /// Settings that can't be read say so first; a relay hooked already is
    /// installed, from wherever it runs; otherwise it is absent, or can't
    /// be installed from this version.
    func state() -> HookState {
        let settings: [String: Any]
        do {
            settings = try read().settings
        } catch let Failure.unreadable(reason) {
            return .unreadable(reason)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        if Self.isInstalled(settings) { return .installed }
        return hasRelay ? .absent : .noRelay
    }

    // MARK: - Installing and removing

    /// Copies the relay, runnable, over any older copy, then hooks it in.
    func install() throws {
        guard let relaySource, hasRelay else { throw Failure.noRelay }
        let (settings, original) = try read()
        try copyRelay(Data(contentsOf: relaySource))
        let installed = Self.install(into: settings, command: Self.command(for: relayDestination))
        try write(installed, over: settings, original: original)
    }

    /// At launch: the hook installed, the copy is brought up to the relay
    /// this version ships, an update of the app having changed it, and
    /// made again if it went. Nothing when the hook isn't installed, the
    /// app has no relay, or the copy is the same already.
    func refreshRelay() throws {
        guard state() == .installed, let relaySource, hasRelay else { return }
        let shipped = try Data(contentsOf: relaySource)
        guard (try? Data(contentsOf: relayDestination)) != shipped else { return }
        try copyRelay(shipped)
    }

    /// Takes every entry running the relay out. The copy of the relay
    /// stays: nothing runs it any more.
    func remove() throws {
        let (settings, original) = try read()
        try write(Self.remove(from: settings), over: settings, original: original)
    }

    // MARK: - The file

    private var hasRelay: Bool {
        relaySource.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// The relay written where it stays put, runnable.
    private func copyRelay(_ relay: Data) throws {
        try FileManager.default.createDirectory(at: relayDestination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try relay.write(to: relayDestination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: relayDestination.path)
    }

    /// The file a symbolic link points at, written in its place.
    private var target: URL { settingsURL.resolvingSymlinksInPath() }

    /// The settings and their bytes as they are; no file yet is no
    /// setting. Anything that isn't settings Claude Code reads throws.
    private func read() throws -> (settings: [String: Any], original: Data?) {
        guard FileManager.default.fileExists(atPath: target.path) else { return ([:], nil) }
        let data: Data
        let object: Any
        do {
            data = try Data(contentsOf: target)
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            let parser = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw Failure.unreadable(parser ?? error.localizedDescription)
        }
        guard let settings = object as? [String: Any], Self.hasReadableHooks(settings) else {
            throw Failure.unreadable(loc("ce ne sont pas des réglages que Claude Code lit",
                                         en: "these are not settings Claude Code reads"))
        }
        return (settings, data)
    }

    /// Writes `settings` in place of `previous`. The bytes as they were go
    /// aside first, the first time only: that copy is the settings before
    /// Claudio, and no later write replaces it. Unchanged, nothing is
    /// written, not even a copy. Indented with sorted keys, slashes left as
    /// they are; the file, and its copy, under the permissions it had.
    private func write(_ settings: [String: Any], over previous: [String: Any], original: Data?) throws {
        guard !NSDictionary(dictionary: settings).isEqual(to: previous) else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = try? manager.attributesOfItem(atPath: target.path)[.posixPermissions]
        if let original, !manager.fileExists(atPath: backupURL.path) {
            try original.write(to: backupURL, options: .atomic)
            if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: backupURL.path) }
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
        if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
    }
}

extension ClaudeCodeHookInstaller.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): reason
        case .noRelay: loc("Relais absent de cette version", en: "No relay in this version")
        }
    }
}
