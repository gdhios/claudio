import XCTest
@testable import Claudio

/// Where the Ulanzi is, and whether there is one at all. No address is the
/// off switch: until one is typed, nothing about the clock is ever sent
/// anywhere. The address is typed by hand, like Ollama's, and read by the
/// same rule. Each test writes to throwaway defaults held in memory, never
/// to this Mac's preferences.
final class AppSettingsUlanziTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// A fresh install has no clock: the bridge stays off.
    func testWithNothingStoredThereIsNoDevice() {
        XCTAssertNil(AppSettings.ulanziAddress(in: defaults))
    }

    /// The address comes back as it was set, kept as its absolute string.
    func testAnAddressSetIsTheAddressRead() {
        let address = URL(string: "http://192.168.1.22")!
        AppSettings.setUlanziAddress(address, in: defaults)

        XCTAssertEqual(AppSettings.ulanziAddress(in: defaults), address)
        XCTAssertEqual(defaults.string(forKey: "ulanziURL"), "http://192.168.1.22")
    }

    /// Switching the face off takes the key away rather than storing an
    /// empty one: nothing is left behind to read as an address.
    func testClearingTheAddressRemovesTheKey() {
        AppSettings.setUlanziAddress(URL(string: "http://192.168.1.22")!, in: defaults)
        AppSettings.setUlanziAddress(nil, in: defaults)

        XCTAssertNil(defaults.object(forKey: AppSettings.ulanziAddressKey))
        XCTAssertNil(AppSettings.ulanziAddress(in: defaults))
    }

    /// A value nobody could call, written by hand or by another version, is
    /// no device rather than a request sent nowhere.
    func testABlankOrUnreadableStoredValueIsNoDevice() {
        for stored in ["", "   ", "ftp://192.168.1.22", "http://"] {
            defaults.set(stored, forKey: AppSettings.ulanziAddressKey)
            XCTAssertNil(AppSettings.ulanziAddress(in: defaults), stored)
        }
    }

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

    /// The storage key is part of the contract: renaming it would forget
    /// every address typed so far.
    func testItIsStoredUnderItsOwnKey() {
        XCTAssertEqual(AppSettings.ulanziAddressKey, "ulanziURL")
    }
}
