import Foundation
import XCTest

/// The wire contract, read from `streamdeck/protocol/fixtures/`. The plugin's
/// TypeScript tests read the very same files, so a field that changes there
/// breaks both sides at once — which is the point.
///
/// The path is derived from `#filePath`, not from a bundled resource: the
/// package declares none, and a copy would quietly drift from the contract.
enum BridgeFixtures {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Bridge
        .deletingLastPathComponent()   // ClaudioTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the repository
        .appendingPathComponent("streamdeck/protocol/fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    }

    /// The fixture decoded into the value the app works with.
    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }

    /// The fixture as a JSON object, for the tests that look at the keys
    /// themselves rather than at a decoded value.
    static func object(_ name: String) throws -> [String: Any] {
        try object(in: data(name))
    }

    static func object(in data: Data) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(parsed as? [String: Any], "the frame is not a JSON object")
    }

    /// Encoding `value` gives the fixture's frame, field for field. Compared
    /// as parsed objects rather than as strings — key order and whitespace
    /// are nobody's business — but with no tolerance anywhere: the numbers
    /// have to land on the fixture's own, not near it.
    static func assertEncoding(_ value: some Encodable, matches name: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try object(in: encoded) as NSDictionary,
                       try object(name) as NSDictionary,
                       "\(name).json", file: file, line: line)
    }
}
