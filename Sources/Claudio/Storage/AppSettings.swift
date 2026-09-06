import Foundation

/// Non-secret settings (UserDefaults). The API key, meanwhile, lives in the Keychain.
enum AppSettings {
    private static let workspaceIDKey = "workspaceID"

    /// Workspace ID (wrkspc_…), required by "identity-linked" keys.
    static var workspaceID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: workspaceIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: workspaceIDKey) }
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
    static var costCounterEnabled: Bool {
        get { UserDefaults.standard.object(forKey: costCounterKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: costCounterKey) }
    }

    // MARK: - Window shortcuts

    private static let windowShortcutsEnabledKey = "windowShortcutsEnabled"

    /// Master switch for the window-snapping shortcuts, on by default. When
    /// off, the shortcuts are unregistered so their keys fall back to whatever
    /// other tool the user runs on them.
    static var windowShortcutsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: windowShortcutsEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: windowShortcutsEnabledKey) }
    }

    // MARK: - Interface language

    private static let languageKey = "language"

    /// Interface language. Missing or unknown value (a setting written by a
    /// future version) falls back to the system's.
    static var language: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: languageKey)
                .flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: languageKey) }
    }

    // MARK: - Panel text size

    private static let panelTextSizeKey = "panelTextSize"

    /// Text size for the floating panel and the palette. Missing or unknown
    /// value (a setting written by a future version) falls back to normal body.
    static var panelTextSize: PanelTextSize {
        get {
            UserDefaults.standard.string(forKey: panelTextSizeKey)
                .flatMap(PanelTextSize.init(rawValue:)) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelTextSizeKey) }
    }

    // MARK: - Custom system prompts

    private static func systemPromptKey(for action: ClaudioAction) -> String {
        "systemPrompt.\(action.rawValue)"
    }

    /// The action's custom system prompt (nil = the code's default prompt).
    static func customSystemPrompt(for action: ClaudioAction) -> String? {
        let value = UserDefaults.standard.string(forKey: systemPromptKey(for: action))
        return (value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? value : nil
    }

    /// nil or empty string: fall back to the default prompt.
    static func setCustomSystemPrompt(_ prompt: String?, for action: ClaudioAction) {
        let key = systemPromptKey(for: action)
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(prompt, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Ollama server

    private static let ollamaBaseURLKey = "ollamaBaseURL"

    /// The Ollama server's address. This machine itself by default, editable
    /// to target another Mac on the local network. An empty or unreadable
    /// value falls back to the default rather than breaking every local action.
    static var ollamaBaseURL: URL {
        get {
            UserDefaults.standard.string(forKey: ollamaBaseURLKey)
                .flatMap(normalizedOllamaURL) ?? Constants.ollamaDefaultURL
        }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: ollamaBaseURLKey) }
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

    // MARK: - Models per action

    private static func modelKey(for action: ClaudioAction) -> String {
        "model.\(action.rawValue)"
    }

    /// The action's custom engine (nil = the code's default). Settings written
    /// before Ollama carried no prefix: `ModelChoice` reads them back.
    static func customModel(for action: ClaudioAction) -> ModelChoice? {
        UserDefaults.standard.string(forKey: modelKey(for: action))
            .flatMap(ModelChoice.init(storageValue:))
    }

    /// nil or identical to the default: fall back to the default (follows app updates).
    static func setCustomModel(_ choice: ModelChoice?, for action: ClaudioAction) {
        let key = modelKey(for: action)
        if let choice, choice != .claude(action.defaultModel) {
            UserDefaults.standard.set(choice.storageValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
