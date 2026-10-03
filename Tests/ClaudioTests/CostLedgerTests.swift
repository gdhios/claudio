import XCTest
@testable import Claudio

/// Locks down the path from tokens to the displayed amount: it's the only
/// thing the user sees of the counter, and a silent drift there would be
/// invisible.
final class CostLedgerTests: XCTestCase {

    /// Anthropic's published rates per million tokens, input / output.
    func testTheRatesAreThePublishedOnes() {
        XCTAssertEqual(ClaudioModel.haiku45.pricing?.input, 1)
        XCTAssertEqual(ClaudioModel.haiku45.pricing?.output, 5)
        XCTAssertEqual(ClaudioModel.sonnet5.pricing?.input, 2)
        XCTAssertEqual(ClaudioModel.sonnet5.pricing?.output, 10)
        XCTAssertEqual(ClaudioModel.opus5.pricing?.input, 5)
        XCTAssertEqual(ClaudioModel.opus5.pricing?.output, 25)
        XCTAssertEqual(ClaudioModel.sonnet55.pricing?.input, 2)
        XCTAssertEqual(ClaudioModel.sonnet55.pricing?.output, 10)
        XCTAssertEqual(ClaudioModel.opus55.pricing?.input, 4)
        XCTAssertEqual(ClaudioModel.opus55.pricing?.output, 20)
    }

    /// A million tokens on each side = the sum of the two rates.
    func testAMillionTokensOnEachSideCostsTheSumOfBothRates() {
        for model in ClaudioModel.bundled {
            XCTAssertEqual(model.cost(inputTokens: 1_000_000, outputTokens: 1_000_000),
                           model.pricing!.input + model.pricing!.output,
                           accuracy: 1e-9, model.id)
        }
    }

    func testTheCostOfAShortAction() {
        // 200 input tokens at $1/MTok + 200 output tokens at $5/MTok.
        XCTAssertEqual(ClaudioModel.haiku45.cost(inputTokens: 200, outputTokens: 200),
                       0.0012, accuracy: 1e-9)
        XCTAssertEqual(ClaudioModel.opus5.cost(inputTokens: 200, outputTokens: 200),
                       0.006, accuracy: 1e-9)
        withLanguage(.french) {
            XCTAssertEqual(ClaudioModel.haiku45.costHint, "≈ 0,12 $ pour 100 actions courtes")
            XCTAssertEqual(ClaudioModel.opus5.costHint, "≈ 0,60 $ pour 100 actions courtes")
        }
    }

    func testMonetaryFormat() {
        withLanguage(.french) {
            XCTAssertEqual(Money.format(0), "0,00 $")
            XCTAssertEqual(Money.format(0.0012), "< 0,01 $")
            XCTAssertEqual(Money.format(0.42), "0,42 $")
            XCTAssertEqual(Money.format(12.5), "12,50 $")
            XCTAssertEqual(Money.formatRounded(5), "5 $")
        }
    }

    /// In English the dollar sign comes first and the separator is the period.
    func testMonetaryFormatEnglish() {
        withLanguage(.english) {
            XCTAssertEqual(Money.format(0), "$0.00")
            XCTAssertEqual(Money.format(0.0012), "< $0.01")
            XCTAssertEqual(Money.format(12.5), "$12.50")
            XCTAssertEqual(Money.formatRounded(5), "$5")
        }
    }

    /// For the length of one assertion, the language is the one under test,
    /// and the machine's setting is restored to what it was.
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        let previous = AppSettings.language
        AppSettings.language = language
        body()
        AppSettings.language = previous
    }

    // MARK: - Daily total

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTheTotalAddsUpWithinTheDay() {
        let start = Calendar.current.startOfDay(for: noon)
        var jour = DailyCost(dayStart: start, total: 0, actions: 0)
        jour = jour.adding(0.10, at: noon)
        jour = jour.adding(0.32, at: noon.addingTimeInterval(3600))
        XCTAssertEqual(jour.total, 0.42, accuracy: 1e-9)
        XCTAssertEqual(jour.actions, 2)
        withLanguage(.french) { XCTAssertEqual(jour.formattedTotal, "0,42 $") }
    }

    func testTheTotalStartsOverAtZeroTheNextDay() {
        let start = Calendar.current.startOfDay(for: noon)
        let veille = DailyCost(dayStart: start, total: 5, actions: 12)
        let lendemain = noon.addingTimeInterval(24 * 3600)

        let apres = veille.adding(0.10, at: lendemain)
        XCTAssertEqual(apres.total, 0.10, accuracy: 1e-9)
        XCTAssertEqual(apres.actions, 1)
        XCTAssertEqual(apres.dayStart, Calendar.current.startOfDay(for: lendemain))

        // Even with no new action, the display doesn't show yesterday's total.
        let affiche = veille.current(at: lendemain)
        XCTAssertEqual(affiche.total, 0)
        XCTAssertEqual(affiche.actions, 0)
        XCTAssertEqual(veille.current(at: noon), veille, "the current day is untouched")
    }

    /// Storage inherited from an earlier version, or empty, must not show up
    /// as today's spend.
    @MainActor
    func testEmptyStorageStartsAtZero() {
        let defaults = InMemoryDefaults()
        let ledger = CostLedger(defaults: defaults, now: noon)
        XCTAssertEqual(ledger.day.total, 0)
        XCTAssertEqual(ledger.day.actions, 0)
    }

    /// A Claude call is a cost; a local call is not, and must inflate neither
    /// the amount nor the count of billed actions.
    @MainActor
    func testOnlyClaudeCallsCountTowardTheSpend() {
        let defaults = InMemoryDefaults()
        let ledger = CostLedger(defaults: defaults, now: noon)

        ledger.record(model: .claude(.haiku45), inputTokens: 200, outputTokens: 200, at: noon)
        XCTAssertEqual(ledger.day.actions, 1)
        XCTAssertEqual(ledger.day.total, 0.0012, accuracy: 1e-9)

        ledger.record(model: .ollama(model: "qwen2.5:14b"),
                      inputTokens: 5_000, outputTokens: 5_000, at: noon)
        XCTAssertEqual(ledger.day.actions, 1, "a local call is not a cost")
        XCTAssertEqual(ledger.day.total, 0.0012, accuracy: 1e-9)
    }

    /// A model the price table doesn't know is still a billed call: it is
    /// counted, adds nothing to the amount, and the amount says so with a
    /// star rather than pretending to be complete.
    @MainActor
    func testACallToAnUnpricedModelIsCountedAndStarred() {
        let defaults = InMemoryDefaults()
        let ledger = CostLedger(defaults: defaults, now: noon)
        ledger.record(model: .claude(.haiku45), inputTokens: 200, outputTokens: 200, at: noon)
        ledger.record(model: .claude(ClaudioModel(id: "claude-sonnet-9")),
                      inputTokens: 200, outputTokens: 200, at: noon)
        XCTAssertEqual(ledger.day.actions, 2)
        XCTAssertEqual(ledger.day.unpricedActions, 1)
        XCTAssertEqual(ledger.day.total, 0.0012, accuracy: 1e-9)
        withLanguage(.french) {
            XCTAssertEqual(ledger.day.formattedTotal, "< 0,01 $*")
        }

        // The star survives a restart, and the day's rollover clears it.
        let reopened = CostLedger(defaults: defaults, now: noon)
        XCTAssertEqual(reopened.day.unpricedActions, 1)
        XCTAssertEqual(reopened.day.current(at: noon.addingTimeInterval(24 * 3600)).unpricedActions, 0)
    }
}
