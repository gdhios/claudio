import Foundation

/// Non-secret settings (UserDefaults). The API key, meanwhile, lives in the
/// Keychain, and each shortcut's model in its `ModelSlot`. A setting that
/// code with injected defaults reads takes `in defaults:`; one only the
/// interface reads is a plain property on the standard defaults.
enum AppSettings {
    private static var standard: UserDefaults { .standard }

    private static let workspaceIDKey = "workspaceID"

    /// Workspace ID (wrkspc_…), required by "identity-linked" keys.
    static var workspaceID: String? {
        get { standard.nonBlankString(workspaceIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        set { standard.setNonBlank(newValue, forKey: workspaceIDKey) }
    }

    /// Same as for the key: the environment variable takes priority in dev.
    static func currentWorkspaceID() -> String? {
        if let env = ProcessInfo.processInfo.environment[Constants.workspaceIDEnvVar],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        return workspaceID
    }

    // MARK: - Cost counter

    private static let costCounterKey = "costCounterEnabled"

    /// Local running total of today's spend, on by default and can be turned
    /// off: the calculation happens on the machine, nothing is sent anywhere.
    static func costCounterEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.flag(costCounterKey)
    }

    static func setCostCounterEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: costCounterKey)
    }

    // MARK: - Window shortcuts

    private static let windowShortcutsEnabledKey = "windowShortcutsEnabled"

    /// Master switch for the window-snapping shortcuts, on by default. When
    /// off, the shortcuts are unregistered so their keys fall back to whatever
    /// other tool the user runs on them.
    static var windowShortcutsEnabled: Bool {
        get { standard.flag(windowShortcutsEnabledKey) }
        set { standard.set(newValue, forKey: windowShortcutsEnabledKey) }
    }

    // MARK: - Interface language

    private static let languageKey = "language"

    /// Interface language. Missing or unknown value (a setting written by a
    /// future version) falls back to the system's.
    static var language: AppLanguage {
        get { standard.choice(languageKey, default: .system) }
        set { standard.set(newValue.rawValue, forKey: languageKey) }
    }

    // MARK: - Panel text size

    private static let panelTextSizeKey = "panelTextSize"

    /// Text size for the floating panel and the palette. Missing or unknown
    /// value (a setting written by a future version) falls back to normal body.
    static var panelTextSize: PanelTextSize {
        get { standard.choice(panelTextSizeKey, default: .normal) }
        set { standard.set(newValue.rawValue, forKey: panelTextSizeKey) }
    }

    // MARK: - Custom system prompts

    private static func systemPromptKey(for action: ClaudioAction) -> String {
        "systemPrompt.\(action.rawValue)"
    }

    /// The action's custom system prompt (nil = the code's default prompt).
    static func customSystemPrompt(for action: ClaudioAction) -> String? {
        standard.nonBlankString(systemPromptKey(for: action))
    }

    /// nil or empty string: fall back to the default prompt.
    static func setCustomSystemPrompt(_ prompt: String?, for action: ClaudioAction) {
        standard.setNonBlank(prompt, forKey: systemPromptKey(for: action))
    }

    // MARK: - Ollama server

    private static let ollamaBaseURLKey = "ollamaBaseURL"

    /// The Ollama server's address. This machine itself by default, editable
    /// to target another Mac on the local network. An empty or unreadable
    /// value falls back to the default rather than breaking every local action.
    static var ollamaBaseURL: URL {
        get {
            standard.string(forKey: ollamaBaseURLKey)
                .flatMap(normalizedOllamaURL) ?? Constants.ollamaDefaultURL
        }
        set { standard.set(newValue.absoluteString, forKey: ollamaBaseURLKey) }
    }

    /// An address is only usable with an http(s) scheme and a host. The
    /// scheme is implied: "192.168.1.20:11434" typed as-is would otherwise
    /// read as a path, with no host.
    static func normalizedOllamaURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    // MARK: - Stream Deck bridge

    /// A missing key is itself a value: no explicit choice.
    static let streamDeckBridgeKey = "streamDeckBridgeEnabled"

    /// nil = the user never chose; the bridge then follows the plugin's presence.
    static func streamDeckBridgeChoice(in defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: streamDeckBridgeKey) as? Bool
    }

    /// `nil` removes the key rather than storing a third value: a `false`
    /// left behind would keep the bridge off even after the plugin is
    /// installed, which is the one thing automatic is meant to spare.
    static func setStreamDeckBridgeChoice(_ choice: Bool?, in defaults: UserDefaults = .standard) {
        if let choice {
            defaults.set(choice, forKey: streamDeckBridgeKey)
        } else {
            defaults.removeObject(forKey: streamDeckBridgeKey)
        }
    }

    /// Whether the bridge listens. Installing the plugin is the whole setup —
    /// nothing to switch on — and an explicit choice outranks it in both
    /// directions: no socket for whoever said no, a socket for whoever keeps
    /// their plugin somewhere this can't see.
    static func streamDeckBridgeEnabled(pluginInstalled: Bool,
                                        in defaults: UserDefaults = .standard) -> Bool {
        streamDeckBridgeChoice(in: defaults) ?? pluginInstalled
    }
}
