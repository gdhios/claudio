import XCTest
@testable import Claudio

/// A Claude model is now a value built from its API identifier, so a model
/// the app has never heard of still reads, prices itself when the table
/// knows it, and shows up with a readable name.
final class ClaudioModelTests: XCTestCase {

    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
        AppSettings.language = .french
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    // MARK: - Identity

    /// The identifier is the whole identity: two values with the same id are
    /// the same model, whatever name the API gave one of them.
    func testTheIdentifierIsTheIdentity() {
        XCTAssertEqual(ClaudioModel(id: "claude-sonnet-5-5"),
                       ClaudioModel(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5"))
        XCTAssertEqual(ClaudioModel.sonnet55.rawValue, "claude-sonnet-5-5")
        XCTAssertEqual(ClaudioModel.opus55.rawValue, "claude-opus-5-5")
    }

    /// Only Claude identifiers are models: anything else is a setting
    /// written by something that isn't this app.
    func testOnlyClaudeIdentifiersAreModels() {
        XCTAssertNotNil(ClaudioModel(rawValue: "claude-haiku-4-5"))
        XCTAssertNotNil(ClaudioModel(rawValue: "claude-future-9"))
        XCTAssertNil(ClaudioModel(rawValue: "gpt-4"))
        XCTAssertNil(ClaudioModel(rawValue: "claude-"))
        XCTAssertNil(ClaudioModel(rawValue: ""))
        XCTAssertNil(ClaudioModel(rawValue: "raw"))
    }

    // MARK: - Names

    /// Without a name from the API, the identifier reads well enough.
    func testANameIsDerivedFromTheIdentifier() {
        XCTAssertEqual(ClaudioModel.derivedName(fromID: "claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(ClaudioModel.derivedName(fromID: "claude-haiku-4-5"), "Haiku 4.5")
        XCTAssertEqual(ClaudioModel.derivedName(fromID: "claude-opus-5"), "Opus 5")
        XCTAssertEqual(ClaudioModel.derivedName(fromID: "claude-opus-4-1-20250805"), "Opus 4.1 (2025-08-05)")
        XCTAssertEqual(ClaudioModel.derivedName(fromID: "claude-3-5-sonnet-20241022"), "Sonnet 3.5 (2024-10-22)")
    }

    /// The API's name wins when there is one, without the "Claude " the
    /// picker would repeat on every line.
    func testTheAPIsNameWinsWithoutThePrefix() {
        let model = ClaudioModel(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5")
        XCTAssertEqual(model.shortName, "Sonnet 5.5")
        XCTAssertEqual(ClaudioModel(id: "claude-sonnet-5-5").shortName, "Sonnet 5.5")
    }

    /// The three historical names must not move: they're what the picker
    /// has shown since the first version.
    func testTheHistoricalDisplayNamesDontChange() {
        XCTAssertEqual(ClaudioModel.haiku45.displayName, "Haiku 4.5 (rapide et économique)")
        XCTAssertEqual(ClaudioModel.sonnet5.displayName, "Sonnet 5 (qualité supérieure)")
        XCTAssertEqual(ClaudioModel.opus5.displayName, "Opus 5 (le plus capable)")
        XCTAssertEqual(ClaudioModel.sonnet55.displayName, "Sonnet 5.5 (qualité supérieure)")
        XCTAssertEqual(ClaudioModel(id: "claude-future-9").displayName, "Future 9")
    }

    func testTheFamilyComesFromTheIdentifier() {
        XCTAssertEqual(ClaudioModel.haiku45.family, .haiku)
        XCTAssertEqual(ClaudioModel.sonnet55.family, .sonnet)
        XCTAssertEqual(ClaudioModel(id: "claude-opus-4-1-20250805").family, .opus)
        XCTAssertEqual(ClaudioModel(id: "claude-future-9").family, .other)
    }

    // MARK: - Pricing

    /// Prices are a local table keyed by the exact identifier: a model the
    /// table doesn't know costs nothing on paper and says so, rather than
    /// borrowing its family's price.
    func testAnUnknownModelHasNoPriceAndSaysSo() {
        let unknown = ClaudioModel(id: "claude-sonnet-9")
        XCTAssertNil(unknown.pricing)
        XCTAssertEqual(unknown.cost(inputTokens: 1_000_000, outputTokens: 1_000_000), 0)
        XCTAssertEqual(unknown.costHint, "Tarif non connu de cette version de Claudio")
        XCTAssertNil(unknown.priceLine)
        XCTAssertEqual(ClaudioModel.sonnet55.priceLine, "Sonnet 5.5 2 $ / 10 $")
    }

    // MARK: - Temperature

    /// `temperature` is a 400 on every model since 4.6: it only goes to the
    /// closed list of old models known to take it, never to a newcomer.
    func testTemperatureOnlyGoesToTheClosedListOfOldModels() {
        XCTAssertTrue(ClaudioModel.haiku45.supportsTemperature)
        XCTAssertFalse(ClaudioModel.sonnet55.supportsTemperature)
        XCTAssertFalse(ClaudioModel.opus55.supportsTemperature)
        XCTAssertFalse(ClaudioModel(id: "claude-haiku-9").supportsTemperature)
    }

    // MARK: - The bundled list

    /// The list the app ships, grouped by family and newest first: it is the
    /// whole picker without network, and the floor the API list adds to.
    func testTheBundledListIsGroupedByFamilyNewestFirst() {
        XCTAssertEqual(ClaudioModel.bundled.map(\.id),
                       ["claude-haiku-4-5", "claude-sonnet-5-5", "claude-sonnet-5",
                        "claude-opus-5-5", "claude-opus-5"])
        XCTAssertTrue(ClaudioModel.bundled.allSatisfy { $0.pricing != nil },
                      "every bundled model ships with its price")
    }
}
