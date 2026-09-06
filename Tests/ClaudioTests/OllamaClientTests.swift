import XCTest
@testable import Claudio

/// The local engine goes through this client: NDJSON parsing decides the
/// displayed and pasted text, the "truncated" badge, and the tokens read;
/// the request body decides what Ollama accepts. These tests pin it against
/// /api/chat-format transcripts, without touching the network.
final class OllamaClientTests: XCTestCase {

    /// Feeds a transcript to the parser, checking along the way that the
    /// fragments delivered as they stream in recompose exactly the final text:
    /// that's what the panel displays during the stream.
    private func parse(_ lines: [String]) throws -> OllamaStreamParser {
        var parser = OllamaStreamParser()
        var pieces = ""
        for line in lines {
            if let piece = try parser.consume(line: line) { pieces += piece }
        }
        XCTAssertEqual(pieces, parser.text)
        return parser
    }

    /// An ordinary response: one complete JSON object per line, the last one
    /// carrying the counts.
    private let ordinaryResponse = [
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":"Bon"},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":"jour"},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":" tout le monde."},"done":false}"#,
        #"{"model":"qwen2.5:14b","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":26,"eval_count":298}"#
    ]

    func testOrdinaryResponseGivesTextAndTokens() throws {
        let parser = try parse(ordinaryResponse)
        XCTAssertEqual(parser.text, "Bonjour tout le monde.")
        XCTAssertFalse(parser.truncated)
        // Both counts are announced only on the final line.
        XCTAssertEqual(parser.inputTokens, 26)
        XCTAssertEqual(parser.outputTokens, 298)
        XCTAssertEqual(parser.result.text, "Bonjour tout le monde.")
    }

    /// The output budget reached: that's what lights up "Retry +".
    func testDoneReasonLengthMarksTruncation() throws {
        let parser = try parse([
            #"{"message":{"role":"assistant","content":"Un début de phrase qui"},"done":false}"#,
            #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length","prompt_eval_count":12,"eval_count":512}"#
        ])
        XCTAssertEqual(parser.text, "Un début de phrase qui")
        XCTAssertTrue(parser.truncated)
        XCTAssertEqual(parser.outputTokens, 512)
    }

    /// A stream interrupted before its final line announces no tokens: none
    /// are invented, and the text already received stays displayable.
    func testAnInterruptedStreamKeepsItsTextAndNoTokens() throws {
        let parser = try parse([
            #"{"message":{"role":"assistant","content":"Moitié"},"done":false}"#
        ])
        XCTAssertEqual(parser.text, "Moitié")
        XCTAssertFalse(parser.truncated)
        XCTAssertEqual(parser.inputTokens, 0)
        XCTAssertEqual(parser.outputTokens, 0)
    }

    /// Ollama can slip an error in mid-stream: it must propagate, not get
    /// lost in truncated text that would get pasted anyway.
    func testAnErrorMidStreamPropagates() {
        XCTAssertThrowsError(try parse([
            #"{"message":{"role":"assistant","content":"Déb"},"done":false}"#,
            #"{"error":"model runner has unexpectedly stopped"}"#
        ])) { error in
            guard case OllamaError.stream(let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(message, "model runner has unexpectedly stopped")
        }
    }

    /// A blank or unreadable line is skipped: it must neither break the
    /// stream nor pollute the text.
    func testAnUnreadableLineIsIgnored() throws {
        let parser = try parse([
            "",
            "{ ceci n'est pas du JSON",
            #"{"message":{"role":"assistant","content":"Intact"},"done":true,"done_reason":"stop"}"#
        ])
        XCTAssertEqual(parser.text, "Intact")
    }

    // MARK: - Request Body

    func testTheRequestBodyIsWhatOllamaExpects() throws {
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

        // The output budget and temperature live under `options`: set at the
        // root, Ollama silently ignores them.
        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["num_predict"] as? Int, 512)
        XCTAssertEqual(options?["temperature"] as? Double, Constants.temperature)
        XCTAssertNil(body["max_tokens"], "num_predict is the name Ollama expects")

        // And it must go out over the network exactly as it is.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// Hybrid models (qwen3.5, qwen3...) think before answering unless told
    /// not to: thinking devours the whole `num_predict` budget and the answer
    /// never arrives. The body always disables it (a model with no thinking
    /// mode just ignores the field without complaint) and sets what keeps the
    /// model warm itself, so it doesn't depend on the server.
    func testTheBodyDisablesThinkingAndKeepsTheModelWarm() {
        let body = OllamaClient.makeBody(text: "Bonjour", system: "Corrige.",
                                         model: "qwen3.5:4b", maxTokens: 512)
        XCTAssertEqual(body["think"] as? Bool, false)
        XCTAssertEqual(body["keep_alive"] as? String, Constants.ollamaKeepAlive)
        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["num_ctx"] as? Int, Constants.ollamaContextLength)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// The context window is fixed: changing it from one request to the next
    /// forces Ollama to reload the model. It only grows, in steps, for an
    /// input that wouldn't fit otherwise, since Ollama would silently
    /// truncate the input and the action would work on a mutilated text.
    func testTheContextWindowOnlyGrowsForLongTexts() {
        XCTAssertEqual(OllamaClient.contextLength(text: "Bonjour", system: "Corrige.", maxTokens: 512),
                       Constants.ollamaContextLength)

        let long = String(repeating: "a", count: 40_000)  // ~10,000 tokens
        let fenetre = OllamaClient.contextLength(text: long, system: "Corrige.", maxTokens: 8192)
        XCTAssertGreaterThanOrEqual(fenetre, 10_000 + 8192)
        XCTAssertEqual(fenetre % 4096, 0, "steps, not one value per text")
        let options = OllamaClient.makeBody(text: long, system: "Corrige.",
                                            model: "qwen3.5:4b", maxTokens: 8192)["options"] as? [String: Any]
        XCTAssertEqual(options?["num_ctx"] as? Int, fenetre)
    }

    // MARK: - Installed Models

    func testTheModelListReadsNames() throws {
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

    // MARK: - Errors

    /// The most common failure of the local engine: the server isn't
    /// running. The message must name the targeted URL, not a URLSession
    /// code.
    func testTheDeadServerNamesItsURL() {
        let previous = AppSettings.language
        AppSettings.language = .french
        defer { AppSettings.language = previous }

        let message = OllamaError.notReachable(url: Constants.ollamaDefaultURL).localizedDescription
        XCTAssertEqual(message, "Ollama ne répond pas sur http://localhost:11434 — est-il lancé ?")

        // Model missing from disk: the fix is a single command.
        let absent = OllamaError.http(status: 404, message: "model 'qwen2.5:14b' not found")
            .localizedDescription
        XCTAssertTrue(absent.contains("ollama pull"), absent)
    }

    // MARK: - Server Address

    /// The address is typed by hand in Settings: it must tolerate the short
    /// form, and reject what's not reachable rather than break every local
    /// action.
    func testTheServerAddressToleratesTheShortForm() {
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

    func testTheHTTPErrorMessageComesFromTheErrorField() {
        XCTAssertEqual(
            OllamaClient.apiErrorMessage(from: Data(#"{"error":"model 'x' not found"}"#.utf8)),
            "model 'x' not found")
        XCTAssertEqual(OllamaClient.apiErrorMessage(from: Data("502 Bad Gateway".utf8)),
                       "502 Bad Gateway")
    }
}
