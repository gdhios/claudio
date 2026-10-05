import XCTest
@testable import Claudio

/// A Claude Code hook's JSON, as the relay hands it on untouched: the four
/// events the hub acts on, the keys it reads, and what is no event at all.
final class ClaudeCodeEventTests: XCTestCase {

    private func event(_ json: String) -> ClaudeCodeEvent? {
        ClaudeCodeEvent(Data(json.utf8))
    }

    /// The end of a turn, with the session, the folder and the last message.
    /// The keys the hub doesn't read are left aside.
    func testAStopCarriesTheLastMessage() {
        let stop = event(#"""
            {"hook_event_name":"Stop","session_id":"5f0c2a9e-1111","cwd":"/Users/g/BAGUETTE",
             "transcript_path":"/x.jsonl","stop_hook_active":false,"last_assistant_message":"🟩 ok"}
            """#)
        XCTAssertEqual(stop, ClaudeCodeEvent(kind: .stop, sessionID: "5f0c2a9e-1111",
                                             cwd: "/Users/g/BAGUETTE", lastAssistantMessage: "🟩 ok"))
    }

    /// A notification carries its type, which decides whether it waits.
    func testANotificationCarriesItsType() {
        let notification = event(#"""
            {"hook_event_name":"Notification","session_id":"s1","cwd":"/a",
             "notification_type":"permission_prompt","message":"Claude needs your permission"}
            """#)
        XCTAssertEqual(notification?.kind, .notification(type: "permission_prompt"))
        XCTAssertNil(notification?.lastAssistantMessage)
    }

    /// A notification without a type is one of no type.
    func testANotificationWithoutATypeHasAnEmptyOne() {
        XCTAssertEqual(event(#"{"hook_event_name":"Notification","session_id":"s1"}"#)?.kind,
                       .notification(type: ""))
    }

    /// A prompt sent, a session ended, and any other hook.
    func testTheOtherEventsAreNamedByTheirHook() {
        XCTAssertEqual(event(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"go"}"#)?.kind,
                       .promptSubmitted)
        XCTAssertEqual(event(#"{"hook_event_name":"SessionEnd","session_id":"s1","reason":"exit"}"#)?.kind,
                       .sessionEnded)
        XCTAssertEqual(event(#"{"hook_event_name":"PreToolUse","session_id":"s1"}"#)?.kind, .other)
    }

    /// The folder and the message are optional; the session is not.
    func testTheFolderAndTheMessageMayBeMissing() {
        let stop = event(#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        XCTAssertEqual(stop, ClaudeCodeEvent(kind: .stop, sessionID: "s1", cwd: nil, lastAssistantMessage: nil))
    }

    /// No session, or no hook name, is no event: nothing to hold an alert
    /// for, nothing to decide.
    func testWithoutASessionOrAHookNameThereIsNoEvent() {
        XCTAssertNil(event(#"{"hook_event_name":"Stop","cwd":"/a"}"#))
        XCTAssertNil(event(#"{"hook_event_name":"Stop","session_id":""}"#))
        XCTAssertNil(event(#"{"hook_event_name":"Stop","session_id":42}"#))
        XCTAssertNil(event(#"{"session_id":"s1"}"#))
    }

    /// And what isn't a JSON object is no event either.
    func testWhatIsNotAJSONObjectIsNoEvent() {
        XCTAssertNil(event(""))
        XCTAssertNil(event("Stop"))
        XCTAssertNil(event(#"["Stop"]"#))
    }
}
