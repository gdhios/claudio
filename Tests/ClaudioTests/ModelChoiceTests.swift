import XCTest
@testable import Claudio

/// Le moteur d'une action se stocke en texte dans les réglages : ce qui est
/// verrouillé ici, c'est qu'un réglage écrit hier se relise demain, et qu'un
/// appel local ne coûte rien.
final class ModelChoiceTests: XCTestCase {

    // MARK: - Coût

    func testUnAppelLocalNeCouteRien() {
        XCTAssertEqual(ModelChoice.ollama(model: "qwen2.5:14b")
            .cost(inputTokens: 100_000, outputTokens: 100_000), 0)
        XCTAssertTrue(ModelChoice.ollama(model: "qwen2.5:14b").isLocal)
    }

    func testLeCoutClaudeResteCeluiDuModele() {
        for model in ClaudioModel.allCases {
            XCTAssertEqual(ModelChoice.claude(model).cost(inputTokens: 200, outputTokens: 200),
                           model.cost(inputTokens: 200, outputTokens: 200),
                           accuracy: 1e-12, model.rawValue)
            XCTAssertFalse(ModelChoice.claude(model).isLocal, model.rawValue)
        }
    }

    /// Le repère affiché à côté du sélecteur : le tarif pour Claude, la gratuité
    /// pour le local.
    func testLeRepereDeCoutAnnonceLaGratuiteDuLocal() {
        let previous = AppSettings.language
        AppSettings.language = .french
        defer { AppSettings.language = previous }

        XCTAssertEqual(ModelChoice.ollama(model: "llama3.2").costHint, "Gratuit (local)")
        XCTAssertEqual(ModelChoice.claude(.haiku45).costHint, ClaudioModel.haiku45.costHint)
    }

    // MARK: - Encodage des réglages

    func testUnChoixClaudeSeRelitApresEcriture() {
        for model in ClaudioModel.allCases {
            let choice = ModelChoice.claude(model)
            XCTAssertEqual(choice.storageValue, "claude:\(model.rawValue)")
            XCTAssertEqual(ModelChoice(storageValue: choice.storageValue), choice, model.rawValue)
        }
    }

    /// Le nom d'un modèle Ollama porte sa balise de version après un « : » :
    /// le découpage ne doit se faire que sur le premier.
    func testUnChoixOllamaGardeLesDeuxPointsDeSaVersion() {
        let choice = ModelChoice.ollama(model: "qwen2.5:14b")
        XCTAssertEqual(choice.storageValue, "ollama:qwen2.5:14b")
        XCTAssertEqual(ModelChoice(storageValue: choice.storageValue), choice)
        XCTAssertEqual(ModelChoice(storageValue: "ollama:llama3.2"), .ollama(model: "llama3.2"))
    }

    /// Cas hérité : les réglages écrits avant Ollama ne stockaient que le
    /// rawValue du modèle Claude, sans préfixe. Ils doivent se relire tels quels.
    func testUnReglageHeriteSeRelitEnClaude() {
        XCTAssertEqual(ModelChoice(storageValue: "claude-haiku-4-5"), .claude(.haiku45))
        XCTAssertEqual(ModelChoice(storageValue: "claude-sonnet-5"), .claude(.sonnet5))
        XCTAssertEqual(ModelChoice(storageValue: "claude-opus-5"), .claude(.opus5))
    }

    /// Une valeur qu'on ne sait pas lire (réglage écrit par une version future,
    /// stock corrompu) rend nil : l'action repart alors sur son défaut.
    func testUneValeurIllisibleNeDonneAucunChoix() {
        XCTAssertNil(ModelChoice(storageValue: ""))
        XCTAssertNil(ModelChoice(storageValue: "ollama:"))
        XCTAssertNil(ModelChoice(storageValue: "claude:claude-inconnu-9"))
        XCTAssertNil(ModelChoice(storageValue: "openrouter:mixtral"))
        XCTAssertNil(ModelChoice(storageValue: "gpt-4"))
    }
}
