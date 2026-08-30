import XCTest
@testable import Claudio

/// Verrouille les identités du catalogue : les rawValue partent dans
/// UserDefaults (prompts et modèles personnalisés) et sur le réseau (IDs de
/// modèles). Les renommer perdrait des réglages ou casserait tous les appels —
/// sans qu'aucun autre test le voie.
final class ClaudioCatalogTests: XCTestCase {

    /// Clés de stockage des prompts/modèles personnalisés, et ordre du menu.
    func testLesClesDeStockageDesActionsNeChangentPas() {
        XCTAssertEqual(ClaudioAction.allCases.map(\.rawValue),
                       ["correct", "makePrompt", "expertPrompt", "translateFR",
                        "translateEN", "professionalTone", "summarize", "simplify"])
    }

    /// Les rawValue partent tels quels dans le champ `model` de l'API : une
    /// coquille ici est une erreur immédiate pour toutes les actions du modèle.
    func testLesIdentifiantsDeModelesSontCeuxDeLAPI() {
        XCTAssertEqual(ClaudioModel.allCases.map(\.rawValue),
                       ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5"])
    }

    /// Haiku partout (latence minimale), Sonnet pour la conception de prompt.
    func testLesModelesParDefaut() {
        for action in ClaudioAction.allCases {
            XCTAssertEqual(action.defaultModel,
                           action == .expertPrompt ? .sonnet5 : .haiku45,
                           action.rawValue)
        }
    }

    /// La palette numérote ses lignes de 1 à 9 : au-delà, les rangs promis à
    /// l'écran deviendraient intapables. Ajouter une action de trop demande de
    /// repenser l'affichage, pas seulement d'ajouter un cas.
    @MainActor
    func testLaPaletteTientDansLesRangs1A9() {
        XCTAssertLessThanOrEqual(PaletteCatalog.rows(matching: "").count, 9)
    }

    /// Chaque action doit arriver entière à l'écran : un libellé vide ferait
    /// une ligne de menu ou de palette muette.
    func testChaqueActionPorteTousSesLibelles() {
        for action in ClaudioAction.allCases {
            XCTAssertFalse(action.panelTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.menuTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.paletteTitle.isEmpty, action.rawValue)
            XCTAssertFalse(action.paletteDetail.isEmpty, action.rawValue)
            XCTAssertTrue(action.progressLabel.hasSuffix("…"), action.rawValue)
            XCTAssertFalse(action.defaultSystem.isEmpty, action.rawValue)
        }
    }

    /// Le prompt et l'enrobage vont par deux : un prompt qui annonce
    /// <texte_source> sans que le message ne balise (ou l'inverse) désoriente
    /// le modèle — c'est le bug qui fait « répondre » à la sélection au lieu
    /// de la transformer.
    func testPromptEtEnrobageRestentAccordes() {
        for action in ClaudioAction.allCases {
            let annonceLaBalise = action.defaultSystem.contains("<texte_source>")
            XCTAssertEqual(annonceLaBalise, action.request.wrapsSource, action.rawValue)
        }
    }
}
