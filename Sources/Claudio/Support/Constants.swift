import AppKit

enum Constants {
    static let appName = "Claudio"

    // The model is chosen per action (ClaudioModel + Settings → Prompts).
    static let temperature = 0.2

    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"

    // Local engine: Ollama on this machine. The URL is editable in Settings
    // to target another Mac on the local network.
    static let ollamaDefaultURL = URL(string: "http://localhost:11434")!
    /// The model stays loaded between actions: otherwise Ollama unloads it
    /// after five minutes and the next action pays for a reload.
    static let ollamaKeepAlive = "1h"
    /// Context window requested on every request. Fixed on purpose: Ollama
    /// reloads the model as soon as it changes from one request to the next.
    static let ollamaContextLength = 8192

    static let keychainService = "com.guillaumedhios.claudio"
    static let keychainAccount = "anthropic-api-key"
    static let apiKeyEnvVar = "ANTHROPIC_API_KEY"
    static let workspaceIDEnvVar = "ANTHROPIC_WORKSPACE_ID"

    // Selection capture via simulated ⌘C
    static let copyPollIntervalNs: UInt64 = 20_000_000        // 20 ms between two pasteboard polls
    static let copyTimeout: TimeInterval = 0.3                // give up if nothing was copied

    // Automatic paste
    static let activationDelayNs: UInt64 = 150_000_000        // delay after reactivating the target app
    static let clipboardRestoreDelayNs: UInt64 = 500_000_000  // delay before restoring the clipboard
                                                              // (increase if an app reads the pasteboard slowly)
    static let restoreClipboardAfterPaste = true

    // Update: a plain read of version.json on the site (no data sent).
    static let updateFeedURL = URL(string: "https://claudio.okonoma.com/version.json")!
    static let updateCheckInterval: TimeInterval = 24 * 3600

    // Panel: fixed width, height adapted to content (bounded text area).
    static let panelWidth: CGFloat = 460
    // Text area: a floor high enough that most sentences show without
    // growing the window (about 8 lines at normal body size), and a ceiling
    // beyond which it scrolls instead of growing further. The floor also
    // sets the panel's home size, chosen deliberately.
    static let panelMinTextHeight: CGFloat = 160
    static let panelMaxTextHeight: CGFloat = 380
}
