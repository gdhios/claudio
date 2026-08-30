import Foundation

/// Anthropic facture en dollars : Claudio affiche des dollars plutôt qu'un
/// taux de change inventé. Virgule décimale, comme partout ailleurs dans l'app.
enum Money {
    static func format(_ dollars: Double) -> String {
        if dollars > 0 && dollars < 0.005 { return "< 0,01 $" }
        let rounded = String(format: "%.2f", dollars).replacingOccurrences(of: ".", with: ",")
        return "\(rounded) $"
    }

    /// Sans centimes quand il n'y en a pas : les tarifs par million sont ronds.
    static func formatRounded(_ dollars: Double) -> String {
        dollars == dollars.rounded() ? "\(Int(dollars)) $" : format(dollars)
    }
}

/// Dépense cumulée d'une journée. Type valeur sans dépendance au stockage :
/// c'est lui que les tests exercent.
struct DailyCost: Equatable, Sendable {
    /// Minuit du jour couvert.
    var dayStart: Date
    /// Dollars dépensés depuis ce minuit.
    var total: Double
    /// Nombre d'appels facturés.
    var actions: Int

    /// Ajoute un appel, en repartant de zéro si la journée a tourné.
    func adding(_ dollars: Double, at date: Date, calendar: Calendar = .current) -> DailyCost {
        let start = calendar.startOfDay(for: date)
        guard start == dayStart else {
            return DailyCost(dayStart: start, total: dollars, actions: 1)
        }
        return DailyCost(dayStart: start, total: total + dollars, actions: actions + 1)
    }

    /// Ce qu'on affiche : le total n'a de sens que pour la journée en cours.
    func current(at date: Date, calendar: Calendar = .current) -> DailyCost {
        let start = calendar.startOfDay(for: date)
        return start == dayStart ? self : DailyCost(dayStart: start, total: 0, actions: 0)
    }

    var formattedTotal: String { Money.format(total) }
}

/// Compteur de dépense du jour. Le calcul se fait sur la machine, à partir des
/// jetons que l'API facture réellement ; rien n'est envoyé nulle part. Muet
/// tant que le réglage est désactivé.
@MainActor
final class CostLedger: ObservableObject {
    static let shared = CostLedger()

    private enum Key {
        static let dayStart = "cost.dayStart"
        static let total = "cost.dayTotal"
        static let actions = "cost.dayActions"
    }

    @Published private(set) var day: DailyCost

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        // Sans rien de stocké, `dayStart` vaut la date de référence : jamais
        // aujourd'hui, donc `current` remet à zéro de lui-même.
        let stored = DailyCost(
            dayStart: Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.dayStart)),
            total: defaults.double(forKey: Key.total),
            actions: defaults.integer(forKey: Key.actions)
        )
        day = stored.current(at: now)
    }

    /// Enregistre un appel terminé. Une annulation ou une erreur n'annonce
    /// aucun jeton : on ne compte alors rien plutôt que d'estimer.
    func record(model: ClaudioModel, inputTokens: Int, outputTokens: Int, at date: Date = Date()) {
        guard AppSettings.costCounterEnabled else { return }
        guard inputTokens > 0 || outputTokens > 0 else { return }
        let dollars = model.cost(inputTokens: inputTokens, outputTokens: outputTokens)
        day = day.adding(dollars, at: date)
        persist()
    }

    /// Remet le compteur du jour à zéro.
    func reset(at date: Date = Date()) {
        day = DailyCost(dayStart: Calendar.current.startOfDay(for: date), total: 0, actions: 0)
        persist()
    }

    /// Rattrape un changement de date survenu pendant que l'app tournait.
    func refresh(at date: Date = Date()) {
        let updated = day.current(at: date)
        guard updated != day else { return }
        day = updated
        persist()
    }

    private func persist() {
        defaults.set(day.dayStart.timeIntervalSinceReferenceDate, forKey: Key.dayStart)
        defaults.set(day.total, forKey: Key.total)
        defaults.set(day.actions, forKey: Key.actions)
    }
}
