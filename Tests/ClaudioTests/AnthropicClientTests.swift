import XCTest
@testable import Claudio

/// Every action goes through this client: SSE stream parsing decides the
/// displayed and pasted text, the "truncated" badge, and the tokens the spend
/// counter records; the request body decides what the API accepts.
/// These tests pin it against /v1/messages-format transcripts, without
/// touching the network.
final class AnthropicClientTests: XCTestCase {

    /// The expected labels are French: the suite pins the language rather than
    /// inheriting it from the machine, otherwise it fails on an English runner
    /// (CI) and passes on a French Mac.
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

    /// Feeds a transcript to the parser, checking along the way that the
    /// fragments delivered as they stream in recompose exactly the final text:
    /// that's what the panel displays during the stream.
    private func parse(_ lines: [String]) throws -> AnthropicClient.StreamParser {
        var parser = AnthropicClient.StreamParser()
        var pieces = ""
        for line in lines {
            if let piece = try parser.consume(line: line) { pieces += piece }
        }
        XCTAssertEqual(pieces, parser.text)
        return parser
    }

    /// An ordinary response, as the API sends it: named events, blank lines
    /// between them, a ping in the middle.
    private let ordinaryResponse = [
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

    func testOrdinaryResponseGivesTextAndTokens() throws {
        let parser = try parse(ordinaryResponse)
        XCTAssertEqual(parser.text, "Bonjour tout le monde.")
        XCTAssertFalse(parser.truncated)
        // Input comes from message_start; output is cumulative and the last
        // message_delta wins: 12 replaces the initial 2, it doesn't add to it.
        XCTAssertEqual(parser.inputTokens, 58)
        XCTAssertEqual(parser.outputTokens, 12)

        let result = parser.result
        XCTAssertEqual(result.text, "Bonjour tout le monde.")
        XCTAssertEqual(result.inputTokens, 58)
        XCTAssertEqual(result.outputTokens, 12)
        XCTAssertFalse(result.truncated)
    }

    /// `stop_reason: max_tokens` is what lights up the "Truncated response"
    /// badge and the "Retry +" button.
    func testTruncationIsDetected() throws {
        let parser = try parse([
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Début de rép"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":400}}"#
        ])
        XCTAssertTrue(parser.truncated)
        XCTAssertEqual(parser.text, "Début de rép")
        XCTAssertEqual(parser.outputTokens, 400)
    }

    /// An error signaled mid-stream (overload...) must interrupt with the
    /// API's message, not blend into the text.
    func testAnErrorMidStreamInterrupts() {
        var parser = AnthropicClient.StreamParser()
        _ = try? parser.consume(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Déb"}}"#)
        XCTAssertThrowsError(try parser.consume(
            line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Erreur de flux : Overloaded")
        }
    }

    /// A stream cut off before tokens are announced doesn't invent any: the
    /// spend counter then records nothing rather than an estimate.
    func testAStreamCutOffAnnouncesNoTokens() throws {
        let parser = try parse([
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Bonj"}}"#
        ])
        XCTAssertEqual(parser.text, "Bonj")
        XCTAssertEqual(parser.inputTokens, 0)
        XCTAssertEqual(parser.outputTokens, 0)
    }

    /// The real stream carries lines that hold nothing (event names, comments,
    /// unexpected JSON): they must neither crash nor write anything.
    func testStrayLinesAreIgnored() throws {
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

    // MARK: - HTTP Errors

    /// HTTP errors arrive as plain JSON, not SSE: the API's message must come
    /// out of it to display in the panel.
    func testTheHTTPErrorMessageIsExtracted() {
        let json = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertEqual(AnthropicClient.apiErrorMessage(from: json), "invalid x-api-key")

        // Unreadable response: show what was received rather than nothing.
        let brut = Data("mauvaise passerelle".utf8)
        XCTAssertEqual(AnthropicClient.apiErrorMessage(from: brut), "mauvaise passerelle")
    }

    /// The statuses a user actually encounters carry a message that says what
    /// to do, not a raw code.
    func testCommonHTTPErrorsSpeakPlainly() {
        XCTAssertEqual(AnthropicError.http(status: 401, message: "x").localizedDescription,
                       "Clé API invalide ou révoquée (401). Vérifie-la dans les Réglages.")
        XCTAssertTrue(AnthropicError.http(status: 429, message: "x").localizedDescription.contains("429"))
        XCTAssertTrue(AnthropicError.http(status: 529, message: "x").localizedDescription.contains("529"))
        XCTAssertTrue(AnthropicError.http(status: 500, message: "boom").localizedDescription.contains("boom"))
    }

    // MARK: - Request Body

    func testTheRequestBodyIsWhatTheAPIExpects() throws {
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
        // And it must go out over the network exactly as it is.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    /// `temperature` is accepted by Haiku 4.5 but rejected (400) by the 5
    /// models: sending it to the wrong model would break all of its actions.
    func testTemperatureOnlyGoesToHaiku() {
        for model in ClaudioModel.allCases {
            let body = AnthropicClient.makeBody(text: "t", system: "s", model: model, maxTokens: 64)
            if model.supportsTemperature {
                XCTAssertEqual(body["temperature"] as? Double, Constants.temperature, model.rawValue)
            } else {
                XCTAssertNil(body["temperature"], model.rawValue)
            }
        }
        // The guard itself: only Haiku 4.5 supports it today.
        XCTAssertEqual(ClaudioModel.allCases.filter(\.supportsTemperature), [.haiku45])
    }
}
