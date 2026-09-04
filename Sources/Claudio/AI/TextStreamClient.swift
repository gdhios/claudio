import Foundation

/// Ce qu'une complétion en streaming rapporte, quel que soit le fournisseur :
/// le texte assemblé, la troncature, et les jetons que l'appel a consommés.
struct StreamResult: Sendable {
    let text: String
    let truncated: Bool
    /// Jetons comptés, annoncés par le fournisseur lui-même. Zéro quand le flux
    /// s'interrompt avant de les avoir donnés.
    let inputTokens: Int
    let outputTokens: Int
}

/// Contrat commun à tous les fournisseurs de complétion en streaming.
/// Le modèle et la configuration (clé, URL) sont portés par l'init du client
/// concret : un client = un fournisseur + un modèle donné. L'appelant n'a donc
/// plus à savoir à qui il parle une fois le client construit.
protocol TextStreamClient: Sendable {
    func streamCompletion(
        of text: String,
        system: String,
        maxTokens: Int,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> StreamResult
}
