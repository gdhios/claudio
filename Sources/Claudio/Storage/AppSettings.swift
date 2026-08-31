import Foundation

/// Réglages non secrets (UserDefaults) — la clé API, elle, vit dans le Trousseau.
enum AppSettings {
    private static let workspaceIDKey = "workspaceID"

    /// ID d'espace de travail (wrkspc_…), requis par les clés « liées à l'identité ».
    static var workspaceID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: workspaceIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: workspaceIDKey) }
    }

    /// Comme pour la clé : la variable d'environnement prime en dev.
    static func currentWorkspaceID() -> String? {
        if let env = ProcessInfo.processInfo.environment[Constants.workspaceIDEnvVar],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        return workspaceID
    }

    // MARK: - Compteur de dépense

    private static let costCounterKey = "costCounterEnabled"

    /// Cumul local de la dépense du jour, activé par défaut et désactivable :
    /// le calcul se fait sur la machine, rien n'est envoyé nulle part.
    static var costCounterEnabled: Bool {
        get { UserDefaults.standard.object(forKey: costCounterKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: costCounterKey) }
    }

    // MARK: - Langue de l'interface

    private static let languageKey = "language"

    /// Langue de l'interface. Valeur absente ou inconnue (réglage écrit par
    /// une version future) → celle du système.
    static var language: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: languageKey)
                .flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: languageKey) }
    }

    // MARK: - Taille du texte du panneau

    private static let panelTextSizeKey = "panelTextSize"

    /// Taille du texte du panneau flottant et de la palette. Valeur absente ou
    /// inconnue (réglage écrit par une version future) → le corps normal.
    static var panelTextSize: PanelTextSize {
        get {
            UserDefaults.standard.string(forKey: panelTextSizeKey)
                .flatMap(PanelTextSize.init(rawValue:)) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelTextSizeKey) }
    }

    // MARK: - Prompts système personnalisés

    private static func systemPromptKey(for action: ClaudioAction) -> String {
        "systemPrompt.\(action.rawValue)"
    }

    /// Prompt système personnalisé de l'action (nil = prompt par défaut du code).
    static func customSystemPrompt(for action: ClaudioAction) -> String? {
        let value = UserDefaults.standard.string(forKey: systemPromptKey(for: action))
        return (value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? value : nil
    }

    /// nil ou chaîne vide → retour au prompt par défaut.
    static func setCustomSystemPrompt(_ prompt: String?, for action: ClaudioAction) {
        let key = systemPromptKey(for: action)
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(prompt, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Modèles par action

    private static func modelKey(for action: ClaudioAction) -> String {
        "model.\(action.rawValue)"
    }

    /// Modèle personnalisé de l'action (nil = défaut du code).
    static func customModel(for action: ClaudioAction) -> ClaudioModel? {
        UserDefaults.standard.string(forKey: modelKey(for: action))
            .flatMap(ClaudioModel.init(rawValue:))
    }

    /// nil ou identique au défaut → retour au défaut (suit les mises à jour de l'app).
    static func setCustomModel(_ model: ClaudioModel?, for action: ClaudioAction) {
        let key = modelKey(for: action)
        if let model, model != action.defaultModel {
            UserDefaults.standard.set(model.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
