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
}
