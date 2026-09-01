import Foundation

/// Une transformation libre déjà lancée : sa consigne, et quand. Seule la
/// consigne — le « quoi faire » — est retenue, jamais le texte source ni le
/// résultat.
struct RecentTransform: Codable, Equatable, Sendable {
    var instruction: String
    var date: Date
}

/// Les dernières consignes libres, la plus récente en tête, sans doublon,
/// plafonnées. Type valeur sans dépendance au stockage : c'est lui que les
/// tests exercent.
struct RecentTransforms: Equatable, Sendable {
    /// Plus récente d'abord.
    private(set) var entries: [RecentTransform]

    init(_ entries: [RecentTransform] = []) { self.entries = entries }

    /// Ajoute une consigne en tête. Blanche, elle est ignorée ; déjà présente
    /// (au trait près), elle remonte avec sa nouvelle date plutôt que de se
    /// dédoubler ; au-delà du plafond, la plus ancienne tombe.
    func adding(_ instruction: String, at date: Date, limit: Int = 20) -> RecentTransforms {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var kept = entries.filter { $0.instruction != trimmed }
        kept.insert(RecentTransform(instruction: trimmed, date: date), at: 0)
        return RecentTransforms(Array(kept.prefix(limit)))
    }

    func cleared() -> RecentTransforms { RecentTransforms() }
}

/// Historique des consignes libres, pour les relancer d'un geste sur la
/// sélection courante. Persisté en JSON dans les préférences ; rien n'est
/// envoyé nulle part. Sur le modèle de `CostLedger`.
@MainActor
final class TransformHistory {
    static let shared = TransformHistory()

    private enum Key { static let entries = "history.recentTransforms" }

    private(set) var recents: RecentTransforms

    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = limit
        if let data = defaults.data(forKey: Key.entries),
           let stored = try? JSONDecoder().decode([RecentTransform].self, from: data) {
            recents = RecentTransforms(Array(stored.prefix(limit)))
        } else {
            recents = RecentTransforms()
        }
    }

    /// Enregistre une consigne libre qui vient d'aboutir. Une consigne vide ou
    /// inchangée n'écrit rien.
    func record(_ instruction: String, at date: Date = Date()) {
        let updated = recents.adding(instruction, at: date, limit: limit)
        guard updated != recents else { return }
        recents = updated
        persist()
    }

    /// Oublie tout l'historique.
    func clear() {
        guard !recents.entries.isEmpty else { return }
        recents = recents.cleared()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recents.entries) {
            defaults.set(data, forKey: Key.entries)
        }
    }
}
