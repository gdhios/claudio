import XCTest
@testable import Claudio

/// How an Ulanzi's address is read when typed in its card: like Ollama's,
/// by the same rule. The list of clocks itself is in
/// `AppSettingsUlanziClocksTests`.
final class AppSettingsUlanziTests: XCTestCase {

    /// The address as people type it: a bare IP, sometimes with a space
    /// pasted along. The scheme is implied, or it would read as a path.
    func testABareHostIsCalledOverHTTP() {
        XCTAssertEqual(AppSettings.normalizedUlanziURL("192.168.1.22")?.absoluteString,
                       "http://192.168.1.22")
        XCTAssertEqual(AppSettings.normalizedUlanziURL("  192.168.1.22 \n")?.absoluteString,
                       "http://192.168.1.22")
        XCTAssertEqual(AppSettings.normalizedUlanziURL("https://horloge.local")?.absoluteString,
                       "https://horloge.local")
    }

    /// Only http(s) with a host can be called; anything else is unreadable.
    func testOnlyHTTPWithAHostIsUsable() {
        XCTAssertNil(AppSettings.normalizedUlanziURL(""))
        XCTAssertNil(AppSettings.normalizedUlanziURL("ftp://192.168.1.22"))
        XCTAssertNil(AppSettings.normalizedUlanziURL("http://"))
    }

    /// One rule for every address typed in Settings: the Ulanzi's and
    /// Ollama's are read the same way, whatever is typed.
    func testTheUlanziAndOllamaReadAnAddressTheSameWay() {
        for typed in ["192.168.1.22", " 192.168.1.20:11434 ", "https://horloge.local",
                      "ftp://x", "http://", "", "localhost"] {
            XCTAssertEqual(AppSettings.normalizedUlanziURL(typed),
                           AppSettings.normalizedOllamaURL(typed), typed)
        }
    }
}
