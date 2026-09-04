import XCTest
@testable import Claudio

/// Le moteur local passe par ce client : le parsing du NDJSON décide du texte
/// affiché puis collé, du badge « tronqué » et des jetons lus ; le corps de la
/// requête, de ce qu'Ollama accepte. Ces tests le fixent sur des transcriptions
/// du format /api/chat, sans toucher au réseau.
final class OllamaClientTests: XCTestCase {

    /// Passe une transcription au parseur, en vérifiant au passage que les
    /// fragments livrés au fil de l'eau recomposent exactement le texte final :
    /// c'est eux que le panneau affiche pendant le stream.
    private func parse(_ lines: [String]) throws -> OllamaStreamParser {
        var parser = OllamaStreamParser()
        var pieces = ""
        for line in lines {
            if let piece = try parser.consume(line: line) { pieces += piece }
        }
        XCTAssertEqual(pieces, parser.text)
        return parser
    }

    /// Une réponse ordinaire : un objet JSON complet par ligne, la dernière
    /// portant les comptes.
    private let reponseOrdinaire = [
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":"Bon"},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":"jour"},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":" tout le monde."},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":26,"eval_count":298}"#
    ]

    func testUneReponseOrdinaireDonneTexteEtJetons() throws {
        let parser = try parse(reponseOrdinaire)
        XCTAssertEqual(parser.text, "Bonjour tout le monde.")
        XCTAssertFalse(parser.truncated)
        // Les deux comptes ne sont annoncés que sur la ligne finale.
        XCTAssertEqual(parser.inputTokens, 26)
        XCTAssertEqual(parser.outputTokens, 298)
        XCTAssertEqual(parser.result.text, "Bonjour tout le monde.")
    }

    /// Le budget de sortie atteint : c'est ce qui allume « Réessayer + ».
    func testDoneReasonLengthMarqueLaTroncature() throws {
        let parser = try parse([
            #"{"message":{"role":"assistant","content":"Un début de phrase qui"},"done":false}"#,
            #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length","prompt_eval_count":12,"eval_count":512}"#
        ])
        XCTAssertEqual(parser.text, "Un début de phrase qui")
        XCTAssertTrue(parser.truncated)
        XCTAssertEqual(parser.outputTokens, 512)
    }

    /// Un flux interrompu avant sa ligne finale n'annonce aucun jeton : on
    /// n'en invente pas, le texte déjà reçu reste affichable.
    func testUnFluxInterrompuGardeSonTexteEtAucunJeton() throws {
        let parser = try parse([
            #"{"message":{"role":"assistant","content":"Moitié"},"done":false}"#
        ])
        XCTAssertEqual(parser.text, "Moitié")
        XCTAssertFalse(parser.truncated)
        XCTAssertEqual(parser.inputTokens, 0)
        XCTAssertEqual(parser.outputTokens, 0)
    }

    /// Ollama peut glisser une erreur au milieu du flux : elle doit remonter,
    /// pas se perdre dans un texte tronqué qu'on collerait quand même.
    func testUneErreurEnFluxRemonte() {
        XCTAssertThrowsError(try parse([
            #"{"message":{"role":"assistant","content":"Déb"},"done":false}"#,
            #"{"error":"model runner has unexpectedly stopped"}"#
        ])) { error in
            guard case OllamaError.stream(let message) = error else {
                return XCTFail("erreur inattendue : \(error)")
            }
            XCTAssertEqual(message, "model runner has unexpectedly stopped")
        }
    }

    /// Une ligne vide ou illisible se saute : elle ne doit ni casser le flux,
    /// ni salir le texte.
    func testUneLigneIllisibleEstIgnoree() throws {
        let parser = try parse([
            "",
            "{ ceci n'est pas du JSON",
            #"{"message":{"role":"assistant","content":"Intact"},"done":true,"done_reason":"stop"}"#
        ])
        XCTAssertEqual(parser.text, "Intact")
    }

    // MARK: - Corps de requête

    func testLeCorpsDeRequeteEstCeluiQuOllamaAttend() throws {
        let body = OllamaClient.makeBody(text: "Bonjour", system: "Corrige.",
                                         model: "qwen2.5:14b", maxTokens: 512)
        XCTAssertEqual(body["model"] as? String, "qwen2.5:14b")
        XCTAssertEqual(body["stream"] as? Bool, true)

        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.first?["content"], "Corrige.")
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "Bonjour")

        // Le budget de sortie et la température vivent sous `options` : posés
        // à la racine, Ollama les ignore en silence.
        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["num_predict"] as? Int, 512)
        XCTAssertEqual(options?["temperature"] as? Double, Constants.temperature)
        XCTAssertNil(body["max_tokens"], "num_predict est le nom qu'Ollama attend")

        // Et il doit partir tel quel sur le réseau.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// Les modèles hybrides (qwen3.5, qwen3…) réfléchissent avant de répondre
    /// si on ne le leur interdit pas : la réflexion dévore tout `num_predict`
    /// et la réponse n'arrive jamais. Le corps la coupe toujours — un modèle
    /// sans mode réflexion ignore le champ sans broncher — et pose lui-même
    /// ce qui garde le modèle chaud, pour ne pas dépendre du serveur.
    func testLeCorpsCoupeLaReflexionEtGardeLeModeleChaud() {
        let body = OllamaClient.makeBody(text: "Bonjour", system: "Corrige.",
                                         model: "qwen3.5:4b", maxTokens: 512)
        XCTAssertEqual(body["think"] as? Bool, false)
        XCTAssertEqual(body["keep_alive"] as? String, Constants.ollamaKeepAlive)
        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["num_ctx"] as? Int, Constants.ollamaContextLength)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// La fenêtre de contexte est fixe : la changer d'une requête à l'autre
    /// force Ollama à recharger le modèle. Elle ne grandit, par paliers, que
    /// pour une entrée qui n'y tiendrait pas — sinon Ollama tronque l'entrée
    /// en silence et l'action travaille sur un texte amputé.
    func testLaFenetreDeContexteNeGranditQuePourLesTextesLongs() {
        XCTAssertEqual(OllamaClient.contextLength(text: "Bonjour", system: "Corrige.", maxTokens: 512),
                       Constants.ollamaContextLength)

        let long = String(repeating: "a", count: 40_000)  // ~10 000 jetons
        let fenetre = OllamaClient.contextLength(text: long, system: "Corrige.", maxTokens: 8192)
        XCTAssertGreaterThanOrEqual(fenetre, 10_000 + 8192)
        XCTAssertEqual(fenetre % 4096, 0, "des paliers, pas une valeur par texte")
        let options = OllamaClient.makeBody(text: long, system: "Corrige.",
                                            model: "qwen3.5:4b", maxTokens: 8192)["options"] as? [String: Any]
        XCTAssertEqual(options?["num_ctx"] as? Int, fenetre)
    }

    // MARK: - Modèles installés

    func testLaListeDesModelesLitLesNoms() throws {
        let data = Data(#"""
        {"models":[
          {"name":"qwen2.5:14b","model":"qwen2.5:14b","size":9000000000,"details":{}},
          {"name":"llama3.2:latest","model":"llama3.2:latest","size":2000000000,"details":{}}
        ]}
        """#.utf8)
        XCTAssertEqual(OllamaClient.modelNames(from: data), ["qwen2.5:14b", "llama3.2:latest"])
        XCTAssertEqual(OllamaClient.modelNames(from: Data(#"{"models":[]}"#.utf8)), [])
        XCTAssertEqual(OllamaClient.modelNames(from: Data("pas du JSON".utf8)), [])
    }

    // MARK: - Erreurs

    /// La panne la plus banale du moteur local : le serveur n'est pas lancé.
    /// Le message doit nommer l'URL visée, pas un code d'URLSession.
    func testLeServeurEteintSeDitAvecSonURL() {
        let previous = AppSettings.language
        AppSettings.language = .french
        defer { AppSettings.language = previous }

        let message = OllamaError.notReachable(url: Constants.ollamaDefaultURL).localizedDescription
        XCTAssertEqual(message, "Ollama ne répond pas sur http://localhost:11434 — est-il lancé ?")

        // Modèle absent du disque : la réparation tient en une commande.
        let absent = OllamaError.http(status: 404, message: "model 'qwen2.5:14b' not found")
            .localizedDescription
        XCTAssertTrue(absent.contains("ollama pull"), absent)
    }

    // MARK: - Adresse du serveur

    /// L'adresse se saisit à la main dans les Réglages : elle doit tolérer la
    /// forme courte, et refuser ce qui n'est pas joignable plutôt que de casser
    /// toutes les actions locales.
    func testLAdresseDuServeurTolereLaFormeCourte() {
        XCTAssertEqual(AppSettings.normalizedOllamaURL("192.168.1.20:11434")?.absoluteString,
                       "http://192.168.1.20:11434")
        XCTAssertEqual(AppSettings.normalizedOllamaURL("  http://localhost:11434  ")?.absoluteString,
                       "http://localhost:11434")
        XCTAssertEqual(AppSettings.normalizedOllamaURL("https://mac-atelier.local:11434")?.absoluteString,
                       "https://mac-atelier.local:11434")
        XCTAssertNil(AppSettings.normalizedOllamaURL(""))
        XCTAssertNil(AppSettings.normalizedOllamaURL("   "))
        XCTAssertNil(AppSettings.normalizedOllamaURL("ftp://ailleurs:21"))
    }

    func testLeMessageDErreurHTTPVientDuChampError() {
        XCTAssertEqual(
            OllamaClient.apiErrorMessage(from: Data(#"{"error":"model 'x' not found"}"#.utf8)),
            "model 'x' not found")
        XCTAssertEqual(OllamaClient.apiErrorMessage(from: Data("502 Bad Gateway".utf8)),
                       "502 Bad Gateway")
    }
}
