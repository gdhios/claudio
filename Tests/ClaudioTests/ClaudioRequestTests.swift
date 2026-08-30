import XCTest
@testable import Claudio

/// Verrouille le comportement de `ClaudioRequest` sur celui de la 1.2.3, où
/// `userMessage` et `maxTokens` vivaient encore sur `ClaudioAction`. Toute
/// dérive de ces valeurs change ce que les utilisateurs reçoivent.
final class ClaudioRequestTests: XCTestCase {

    /// 400 caractères → 100 tokens d'entrée estimés, valeurs calculées à la main
    /// depuis les bornes de la 1.2.3.
    private let text = String(repeating: "a", count: 400)

    func testBudgetsReproduisentLesValeursDeLa123() {
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.translateFR.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.translateEN.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.professionalTone.request.maxTokens(forText: text), 328)
        XCTAssertEqual(ClaudioAction.makePrompt.request.maxTokens(forText: text), 556)
        XCTAssertEqual(ClaudioAction.simplify.request.maxTokens(forText: text), 556)
        XCTAssertEqual(ClaudioAction.expertPrompt.request.maxTokens(forText: text), 1268)
        XCTAssertEqual(ClaudioAction.summarize.request.maxTokens(forText: text), 384)
    }

    func testPlanchersEtPlafonds() {
        // Texte vide : le plancher de la forme s'applique.
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: ""), 256)
        XCTAssertEqual(ClaudioAction.summarize.request.maxTokens(forText: ""), 384)
        // Le « Réessayer + » double, sans dépasser le plafond dur.
        XCTAssertEqual(ClaudioAction.correct.request.maxTokens(forText: text, multiplier: 2), 656)
        let enorme = String(repeating: "a", count: 500_000)
        XCTAssertEqual(ClaudioAction.expertPrompt.request.maxTokens(forText: enorme, multiplier: 4), 16384)
    }

    func testSeuleLaCorrectionEnvoieLeTexteNu() {
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

    func testLeCatalogueSeReporteFidelementDansLaRequete() {
        for action in ClaudioAction.allCases {
            let request = action.request
            XCTAssertEqual(request.origin, .catalog(action))
            XCTAssertEqual(request.panelTitle, action.panelTitle)
            XCTAssertEqual(request.progressLabel, action.progressLabel)
            XCTAssertEqual(request.system, action.system)
            XCTAssertEqual(request.model, action.model)
        }
    }

    func testActionLibrePorteLInstructionEtBaliseLaSource() {
        let request = ClaudioRequest.free(instruction: "  Traduis en espagnol  ")
        XCTAssertEqual(request.origin, .free(instruction: "Traduis en espagnol"))
        XCTAssertTrue(request.system.contains("Traduis en espagnol"))
        XCTAssertFalse(request.system.contains("  Traduis"), "l'instruction doit être détourée")
        XCTAssertTrue(request.wrapsSource)
        XCTAssertTrue(request.userMessage(forText: "Le chat dort.").contains("<texte_source>"))
        XCTAssertEqual(request.maxTokens(forText: text), 556)
    }

    /// `needsInstruction` est la porte qui décide d'ouvrir la saisie plutôt que
    /// d'appeler l'API : elle ne doit s'ouvrir que pour l'action libre sans consigne.
    func testSeuleLActionLibreSansConsigneReclameUneSaisie() {
        XCTAssertTrue(ClaudioRequest.awaitingInstruction.needsInstruction)
        XCTAssertFalse(ClaudioRequest.free(instruction: "Traduis en espagnol").needsInstruction)
        XCTAssertTrue(ClaudioRequest.free(instruction: "   ").needsInstruction,
                      "une consigne d'espaces est détourée, donc vide")
        for action in ClaudioAction.allCases {
            XCTAssertFalse(action.request.needsInstruction, "\(action.rawValue)")
        }
    }

    /// Le panneau s'habille avant que la consigne existe : titre et icône de
    /// l'action libre doivent déjà être bons pendant la saisie.
    func testLaRequeteEnAttentePorteDejaLIdentiteDeLActionLibre() {
        let waiting = ClaudioRequest.awaitingInstruction
        XCTAssertEqual(waiting.origin, .free(instruction: ""))
        XCTAssertEqual(waiting.panelTitle, ClaudioRequest.free(instruction: "peu importe").panelTitle)
    }
}
