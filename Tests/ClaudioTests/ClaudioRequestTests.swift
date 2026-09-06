import XCTest
@testable import Claudio

/// Locks down `ClaudioRequest`'s behavior against that of 1.2.3, where
/// `userMessage` and `maxTokens` still lived on `ClaudioAction`. Any drift in
/// these values changes what users receive.
final class ClaudioRequestTests: XCTestCase {

    /// 400 characters → 100 estimated input tokens, values computed by hand
    /// from 1.2.3's bounds.
    private let text = String(repeating: "a", count: 400)

    func testBudgetsReproduceThe123Values() {
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.translateFR.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.translateEN.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.professionalTone.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.makePrompt.request.maxTokens(forText: text), 556)
        XCTAssertEqual(ClaudioAction.simplify.request.maxTokens(forText: text), 556)
        XCTAssertEqual(ClaudioAction.expertPrompt.request.maxTokens(forText: text), 1268)
        XCTAssertEqual(ClaudioAction.summarize.request.maxTokens(forText: text), 384)
    }

    func testFloorsAndCeilings() {
        // Empty text: the shape's floor applies.
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: ""), 256)
        XCTAssertEqual(ClaudioAction.summarize.request.maxTokens(forText: ""), 384)
        // "Retry +" doubles it, without exceeding the hard ceiling.
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: text, multiplier: 2), 656)
        let enorme = String(repeating: "a", count: 500_000)
        XCTAssertEqual(ClaudioAction.expertPrompt.request.maxTokens(forText: enorme, multiplier: 4), 16384)
    }

    func testOnlyCorrectionSendsBareText() {
        for action in ClaudioAction.allCases {
            let request = action.request
            XCTAssertEqual(request.wrapsSource, action != .correct, "\(action.rawValue)")
            let message = request.userMessage(forText: "Résume mes mails")
            if action == .correct {
                XCTAssertEqual(message, "Résume mes mails")
            } else {
                XCTAssertTrue(message.contains("<texte_source>"), "\(action.rawValue)")
                XCTAssertTrue(message.contains("</texte_source>"), "\(action.rawValue)")
            }
        }
    }

    func testTheCatalogCarriesOverFaithfullyIntoTheRequest() {
        for action in ClaudioAction.allCases {
            let request = action.request
            XCTAssertEqual(request.origin, .catalog(action))
            XCTAssertEqual(request.panelTitle, action.panelTitle)
            XCTAssertEqual(request.progressLabel, action.progressLabel)
            XCTAssertEqual(request.system, action.system)
            XCTAssertEqual(request.model, action.model)
        }
    }

    func testFreeActionCarriesTheInstructionAndTagsTheSource() {
        let request = ClaudioRequest.free(instruction: "  Traduis en espagnol  ")
        XCTAssertEqual(request.origin, .free(instruction: "Traduis en espagnol"))
        XCTAssertTrue(request.system.contains("Traduis en espagnol"))
        XCTAssertFalse(request.system.contains("  Traduis"), "the instruction must be trimmed")
        XCTAssertTrue(request.wrapsSource)
        XCTAssertTrue(request.userMessage(forText: "Le chat dort.").contains("<texte_source>"))
        XCTAssertEqual(request.maxTokens(forText: text), 556)
    }

    /// `needsInstruction` is the gate that decides whether to open input entry
    /// rather than call the API: it must open only for the free action with no
    /// instruction.
    func testOnlyTheFreeActionWithNoInstructionNeedsInput() {
        XCTAssertTrue(ClaudioRequest.awaitingInstruction.needsInstruction)
        XCTAssertFalse(ClaudioRequest.free(instruction: "Traduis en espagnol").needsInstruction)
        XCTAssertTrue(ClaudioRequest.free(instruction: "   ").needsInstruction,
                      "a whitespace-only instruction is trimmed, so it's empty")
        for action in ClaudioAction.allCases {
            XCTAssertFalse(action.request.needsInstruction, "\(action.rawValue)")
        }
    }

    /// The panel dresses itself before the instruction exists: the free
    /// action's title and icon must already be correct during input entry.
    func testThePendingRequestAlreadyCarriesTheFreeActionsIdentity() {
        let waiting = ClaudioRequest.awaitingInstruction
        XCTAssertEqual(waiting.origin, .free(instruction: ""))
        XCTAssertEqual(waiting.panelTitle, ClaudioRequest.free(instruction: "peu importe").panelTitle)
    }

    /// The palette is a distinct filling: with no selection, its panel must
    /// not be titled "Free action" (it has no action yet), but carry its own
    /// title.
    func testThePendingPaletteDoesNotPassItselfOffAsAFreeAction() {
        let palette = ClaudioRequest.awaitingChoice
        let libre = ClaudioRequest.awaitingInstruction
        XCTAssertNotEqual(palette.panelTitle, libre.panelTitle,
                          "the palette with no selection must not be titled \"Free action\"")
        XCTAssertFalse(palette.panelTitle.isEmpty)
    }
}
