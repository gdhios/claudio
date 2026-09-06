import XCTest
@testable import Claudio

/// Locks down the catalog's identities: rawValues go into UserDefaults
/// (custom prompts and models) and onto the network (model IDs). Renaming
/// them would lose settings or break every call, with no other test to catch it.
final class ClaudioCatalogTests: XCTestCase {

    /// Storage keys for custom prompts/models, and the menu's order.
    func testTheActionsStorageKeysDontChange() {
        XCTAssertEqual(ClaudioAction.allCases.map(\.rawValue),
                       ["correct", "makePrompt", "expertPrompt", "translateFR",
                        "translateEN", "professionalTone", "summarize", "simplify"])
    }

    /// rawValues go straight into the API's `model` field: a typo here is an
    /// immediate failure for every action of that model.
    func testTheModelIdentifiersAreTheAPIs() {
        XCTAssertEqual(ClaudioModel.allCases.map(\.rawValue),
                       ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5"])
    }

    /// Haiku everywhere (minimal latency), Sonnet for prompt design.
    func testTheDefaultModels() {
        for action in ClaudioAction.allCases {
            XCTAssertEqual(action.defaultModel,
                           action == .expertPrompt ? .sonnet5 : .haiku45,
                           action.rawValue)
        }
    }

    /// The palette numbers its rows 1 through 9: beyond that, the ranks
    /// promised on screen would become untypeable. Adding one action too many
    /// means rethinking the display, not just adding a case.
    @MainActor
    func testThePaletteFitsInRanks1To9() {
        XCTAssertLessThanOrEqual(PaletteCatalog.rows(matching: "").count, 9)
    }

    /// Every action must arrive on screen whole: an empty label would make a
    /// silent menu or palette row.
    func testEveryActionCarriesAllItsLabels() {
        for action in ClaudioAction.allCases {
            XCTAssertFalse(action.panelTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.menuTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.paletteTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.paletteDetail.isEmpty, action.rawValue)
            XCTAssertTrue(action.progressLabel.hasSuffix("…"), action.rawValue)
            XCTAssertFalse(action.defaultSystem.isEmpty, action.rawValue)
        }
    }

    /// The prompt and its wrapping go together: a prompt that announces
    /// <texte_source> without the message tagging it (or the reverse) confuses
    /// the model. That's the bug that makes it "answer" the selection instead
    /// of transforming it.
    func testPromptAndWrappingStayInSync() {
        for action in ClaudioAction.allCases {
            let annonceLaBalise = action.defaultSystem.contains("<texte_source>")
            XCTAssertEqual(annonceLaBalise, action.request.wrapsSource, action.rawValue)
        }
    }
}
