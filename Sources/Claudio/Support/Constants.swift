import AppKit

enum Constants {
    static let appName = "Claudio"

    // ⚠️ `temperature` est accepté sur Haiku 4.5 mais rejeté (400) sur les
    // modèles des générations 4.6+/5 — le retirer du body si on change de modèle.
    static let model = "claude-haiku-4-5"
    static let temperature = 0.2

    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"

    static let keychainService = "com.guillaumedhios.claudio"
    static let keychainAccount = "anthropic-api-key"
    static let apiKeyEnvVar = "ANTHROPIC_API_KEY"
    static let workspaceIDEnvVar = "ANTHROPIC_WORKSPACE_ID"

    // Capture de sélection via ⌘C simulé
    static let copyPollIntervalNs: UInt64 = 20_000_000        // 20 ms entre deux sondages du pasteboard
    static let copyTimeout: TimeInterval = 0.3                // abandon si rien n'est copié

    // Collage automatique
    static let activationDelayNs: UInt64 = 150_000_000        // délai après réactivation de l'app cible
    static let clipboardRestoreDelayNs: UInt64 = 500_000_000  // délai avant restauration du presse-papiers
                                                              // (augmenter si une app lit le pasteboard lentement)
    static let restoreClipboardAfterPaste = true

    // Panneau : largeur fixe, hauteur adaptée au contenu (zone de texte bornée).
    static let panelWidth: CGFloat = 460
    static let panelMaxTextHeight: CGFloat = 380
}
