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
}
