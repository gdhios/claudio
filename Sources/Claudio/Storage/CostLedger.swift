import Foundation

/// Anthropic bills in dollars: Claudio shows dollars rather than a made-up
/// exchange rate. Decimal comma, as everywhere else in the app.
enum Money {
    static func format(_ dollars: Double) -> String {
        // The number's punctuation follows the interface language: comma and
        // dollar sign at the end in French, period and dollar sign in front in English.
        if dollars > 0 && dollars < 0.005 { return loc("< 0,01 $", en: "< $0.01") }
        let amount = String(format: "%.2f", dollars)
        return loc("\(amount.replacingOccurrences(of: ".", with: ",")) $", en: "$\(amount)")
    }

    /// Without cents when there are none: per-million rates are round numbers.
    static func formatRounded(_ dollars: Double) -> String {
        guard dollars == dollars.rounded() else { return format(dollars) }
        return loc("\(Int(dollars)) $", en: "$\(Int(dollars))")
    }
}

/// A day's cumulative spend. A value type with no dependency on storage:
/// it's what the tests exercise.
struct DailyCost: Equatable, Sendable {
    /// Midnight of the day covered.
    var dayStart: Date
    /// Dollars spent since that midnight.
    var total: Double
    /// Number of billed calls.
    var actions: Int

    /// Adds a call, starting over from zero if the day has rolled over.
    func adding(_ dollars: Double, at date: Date, calendar: Calendar = .current) -> DailyCost {
        let start = calendar.startOfDay(for: date)
        guard start == dayStart else {
            return DailyCost(dayStart: start, total: dollars, actions: 1)
        }
        return DailyCost(dayStart: start, total: total + dollars, actions: actions + 1)
    }

    /// What we display: the total only makes sense for the current day.
    func current(at date: Date, calendar: Calendar = .current) -> DailyCost {
        let start = calendar.startOfDay(for: date)
        return start == dayStart ? self : DailyCost(dayStart: start, total: 0, actions: 0)
    }

    var formattedTotal: String { Money.format(total) }
}

/// Today's cost counter. The calculation happens on the machine, from the
/// tokens the API actually bills; nothing is sent anywhere. Silent as long
/// as the setting is off.
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
        // With nothing stored, `dayStart` is the reference date: never
        // today, so `current` resets to zero on its own.
        let stored = DailyCost(
            dayStart: Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.dayStart)),
            total: defaults.double(forKey: Key.total),
            actions: defaults.integer(forKey: Key.actions)
        )
        day = stored.current(at: now)
    }

    /// Records a completed call. A cancellation or an error reports no
    /// tokens: we then count nothing rather than estimate. A local call
    /// costs nothing and so isn't a spend: it inflates neither the amount
    /// nor the count of billed actions.
    func record(model: ModelChoice, inputTokens: Int, outputTokens: Int, at date: Date = Date()) {
        guard !model.isLocal else { return }
        guard AppSettings.costCounterEnabled else { return }
        guard inputTokens > 0 || outputTokens > 0 else { return }
        let dollars = model.cost(inputTokens: inputTokens, outputTokens: outputTokens)
        day = day.adding(dollars, at: date)
        persist()
    }

    /// Resets the day's counter to zero.
    func reset(at date: Date = Date()) {
        day = DailyCost(dayStart: Calendar.current.startOfDay(for: date), total: 0, actions: 0)
        persist()
    }

    /// Catches up with a date change that happened while the app was running.
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
