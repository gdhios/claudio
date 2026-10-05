import XCTest
@testable import Claudio

/// The Mac's IPv4 on the local network, which the clock posts its buttons
/// to: Wi-Fi's (`en0`) first, else the first one that is up and not the
/// loopback.
final class LocalNetworkAddressTests: XCTestCase {

    private typealias Interface = LocalNetworkAddress.Interface

    func testEn0ComesFirstWhereverItIsListed() {
        XCTAssertEqual(LocalNetworkAddress.pick(from: [
            Interface(name: "lo0", address: "127.0.0.1", isLoopback: true, isUp: true),
            Interface(name: "en7", address: "10.0.0.5", isLoopback: false, isUp: true),
            Interface(name: "en0", address: "192.168.1.50", isLoopback: false, isUp: true),
        ]), "192.168.1.50")
    }

    func testWithoutEn0TheFirstOtherAddressServes() {
        XCTAssertEqual(LocalNetworkAddress.pick(from: [
            Interface(name: "lo0", address: "127.0.0.1", isLoopback: true, isUp: true),
            Interface(name: "en7", address: "10.0.0.5", isLoopback: false, isUp: true),
            Interface(name: "utun4", address: "100.64.0.2", isLoopback: false, isUp: true),
        ]), "10.0.0.5")
    }

    /// An interface that is down, en0 included, reaches nobody.
    func testAnInterfaceThatIsDownIsPassedOver() {
        XCTAssertEqual(LocalNetworkAddress.pick(from: [
            Interface(name: "en0", address: "169.254.3.4", isLoopback: false, isUp: false),
            Interface(name: "en7", address: "10.0.0.5", isLoopback: false, isUp: true),
        ]), "10.0.0.5")
    }

    /// The loopback alone is no address on the network.
    func testTheLoopbackAloneIsNoAddress() {
        XCTAssertNil(LocalNetworkAddress.pick(from: [
            Interface(name: "lo0", address: "127.0.0.1", isLoopback: true, isUp: true),
        ]))
        XCTAssertNil(LocalNetworkAddress.pick(from: []))
    }

    /// This Mac's own, read without sending anything: an IPv4 in four
    /// numbers, never the loopback's, or nothing off any network.
    func testThisMacsAddressIsADottedQuadOrNothing() {
        guard let address = LocalNetworkAddress.current() else { return }
        let parts = address.split(separator: ".")
        XCTAssertEqual(parts.count, 4, address)
        XCTAssertTrue(parts.allSatisfy { UInt8($0) != nil }, address)
        XCTAssertFalse(address.hasPrefix("127."), address)
    }
}
