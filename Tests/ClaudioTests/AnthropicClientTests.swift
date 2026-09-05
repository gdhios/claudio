import XCTest
@testable import Claudio

/// Toutes les actions passent par ce client : le parsing du flux SSE décide du
/// texte affiché puis collé, du badge « tronqué » et des jetons que le compteur
/// de dépense enregistre ; le corps de la requête, de ce que l'API accepte.
/// Ces tests le fixent sur des transcriptions du format /v1/messages, sans
/// toucher au réseau.
final class AnthropicClientTests: XCTestCase {

    /// Les libellés attendus sont français : la suite fixe la langue plutôt
    /// que d'hériter de celle de la machine, sinon elle échoue sur un runner
    /// anglais (la CI) et passe sur un Mac français.
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

    /// Passe une transcription au parseur, en vérifiant au passage que les
    /// fragments livrés au fil de l'eau recomposent exactement le texte final :
    /// c'est eux que le panneau affiche pendant le stream.
    private func parse(_ lines: [String]) throws -> AnthropicClient.StreamParser {
        var parser = AnthropicClient.StreamParser()
        var pieces = ""
        for line in lines {
            if let piece = try parser.consume(line: line) { pieces += piece }
        }
        XCTAssertEqual(pieces, parser.text)
        return parser
    }

    /// Une réponse ordinaire, telle que l'API l'envoie : événements nommés,
    /// lignes vides entre eux, ping au milieu.
    private let reponseOrdinaire = [
        "event: message_start",
        #"data: {"type":"message_start","message":{"id":"msg_01X","type":"message","role":"assistant","content":[],"model":"claude-haiku-4-5","usage":{"input_tokens":58,"output_tokens":2}}}"#,
        "",
        "event: content_block_start",
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        "",
        "event: ping",
        #"data: {"type": "ping"}"#,
        "",
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonjour"}}"#,
        "",
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" tout le monde."}}"#,
        "",
        "event: content_block_stop",
        #"data: {"type":"content_block_stop","index":0}"#,
        "",
        "event: message_delta",
        #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}"#,
        "",
        "event: message_stop",
        #"data: {"type":"message_stop"}"#
    ]

    func testUneReponseOrdinaireDonneTexteEtJetons() throws {
        let parser = try parse(reponseOrdinaire)
        XCTAssertEqual(parser.text, "Bonjour tout le monde.")
        XCTAssertFalse(parser.truncated)
        // L'entrée vient de message_start ; la sortie est cumulative et le
        // dernier message_delta fait foi : 12 remplace le 2 initial, il ne s'y
        // ajoute pas.
        XCTAssertEqual(parser.inputTokens, 58)
        XCTAssertEqual(parser.outputTokens, 12)

        let result = parser.result
        XCTAssertEqual(result.text, "Bonjour tout le monde.")
        XCTAssertEqual(result.inputTokens, 58)
        XCTAssertEqual(result.outputTokens, 12)
        XCTAssertFalse(result.truncated)
    }

    /// `stop_reason: max_tokens` est ce qui allume le badge « Réponse
    /// tronquée » et le bouton « Réessayer + ».
    func testLaTroncatureEstDetectee() throws {
        let parser = try parse([
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Début de rép"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":400}}"#
        ])
        XCTAssertTrue(parser.truncated)
        XCTAssertEqual(parser.text, "Début de rép")
        XCTAssertEqual(parser.outputTokens, 400)
    }

    /// Une erreur signalée en plein flux (surcharge…) doit interrompre avec le
    /// message de l'API, pas se fondre dans le texte.
    func testUneErreurDansLeFluxInterrompt() {
        var parser = AnthropicClient.StreamParser()
        _ = try? parser.consume(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Déb"}}"#)
        XCTAssertThrowsError(try parser.consume(
            line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Erreur de flux : Overloaded")
        }
    }

    /// Un flux coupé avant l'annonce des jetons n'en invente pas : le compteur
    /// de dépense n'enregistre alors rien plutôt qu'une estimation.
    func testUnFluxCoupeNAnnonceAucunJeton() throws {
        let parser = try parse([
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonj"}}"#
        ])
        XCTAssertEqual(parser.text, "Bonj")
        XCTAssertEqual(parser.inputTokens, 0)
        XCTAssertEqual(parser.outputTokens, 0)
    }

    /// Le flux réel charrie des lignes qui ne portent rien (noms d'événements,
    /// commentaires, JSON inattendu) : elles ne doivent ni planter ni écrire.
    func testLesLignesEtrangeresSontIgnorees() throws {
        let parser = try parse([
            "event: content_block_delta",
            "",
            ": keep-alive",
            "data: pas du JSON",
            #"data: {"sans_type":1}"#,
            #"data: {"type":"evenement_inconnu"}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        ])
        XCTAssertEqual(parser.text, "")
        XCTAssertFalse(parser.truncated)
    }

    // MARK: - Erreurs HTTP

    /// Les erreurs HTTP arrivent en JSON classique, pas en SSE : le message de
    /// l'API doit en ressortir pour s'afficher dans le panneau.
    func testLeMessageDErreurHTTPEstExtrait() {
        let json = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertEqual(AnthropicClient.apiErrorMessage(from: json), "invalid x-api-key")

        // Réponse illisible : on montre ce qu'on a reçu plutôt que rien.
        let brut = Data("mauvaise passerelle".utf8)
        XCTAssertEqual(AnthropicClient.apiErrorMessage(from: brut), "mauvaise passerelle")
    }

    /// Les statuts que l'utilisateur rencontre vraiment portent un message qui
    /// dit quoi faire, pas un code brut.
    func testLesErreursHTTPCourantesParlentClair() {
        XCTAssertEqual(AnthropicError.http(status: 401, message: "x").localizedDescription,
                       "Clé API invalide ou révoquée (401). Vérifie-la dans les Réglages.")
        XCTAssertTrue(AnthropicError.http(status: 429, message: "x").localizedDescription.contains("429"))
        XCTAssertTrue(AnthropicError.http(status: 529, message: "x").localizedDescription.contains("529"))
        XCTAssertTrue(AnthropicError.http(status: 500, message: "boom").localizedDescription.contains("boom"))
    }

    // MARK: - Corps de requête

    func testLeCorpsDeRequeteEstCeluiQueLAPIAttend() throws {
        let body = AnthropicClient.makeBody(text: "Bonjour", system: "Corrige.",
                                            model: .haiku45, maxTokens: 512)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 512)
        XCTAssertEqual(body["system"] as? String, "Corrige.")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "Bonjour")
        // Et il doit partir tel quel sur le réseau.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// `temperature` est accepté par Haiku 4.5 mais rejeté (400) par les
    /// modèles 5 : l'envoyer au mauvais modèle casserait toutes ses actions.
    func testLaTemperatureNePartQueVersHaiku() {
        for model in ClaudioModel.allCases {
            let body = AnthropicClient.makeBody(text: "t", system: "s", model: model, maxTokens: 64)
            if model.supportsTemperature {
                XCTAssertEqual(body["temperature"] as? Double, Constants.temperature, model.rawValue)
            } else {
                XCTAssertNil(body["temperature"], model.rawValue)
            }
        }
        // Le garde-fou lui-même : seul Haiku 4.5 la supporte aujourd'hui.
        XCTAssertEqual(ClaudioModel.allCases.filter(\.supportsTemperature), [.haiku45])
    }
}
