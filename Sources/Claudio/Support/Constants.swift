import AppKit

enum Constants {
    static let appName = "Claudio"

    // Le modèle se choisit par action (ClaudioModel + Réglages → Prompts).
    static let temperature = 0.2

    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"

    // Moteur local : Ollama sur la machine. L'URL est éditable dans les
    // Réglages pour viser un autre Mac du réseau local.
    static let ollamaDefaultURL = URL(string: "http://localhost:11434")!

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

    // Mise à jour : simple lecture de version.json sur le site (aucune donnée envoyée).
    static let updateFeedURL = URL(string: "https://claudio.okonoma.com/version.json")!
    static let updateCheckInterval: TimeInterval = 24 * 3600

    // Panneau : largeur fixe, hauteur adaptée au contenu (zone de texte bornée).
    static let panelWidth: CGFloat = 460
    // Zone de texte : un plancher assez haut pour que la plupart des phrases
    // s'affichent sans faire grandir la fenêtre (≈ 8 lignes au corps normal), et
    // un plafond au-delà duquel on défile plutôt que d'agrandir encore. Le
    // plancher fixe aussi la taille d'accueil du panneau, volontairement posée.
    static let panelMinTextHeight: CGFloat = 160
    static let panelMaxTextHeight: CGFloat = 380
}
