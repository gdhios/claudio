import Network
import XCTest
@testable import Claudio

/// Where a connection comes from, read off its remote endpoint as a value:
/// this Mac, however a dual-stack listener writes it, or anywhere else.
final class HubPeerTests: XCTestCase {

    private func peer(_ host: NWEndpoint.Host) -> NWEndpoint {
        .hostPort(host: host, port: 51234)
    }

    /// The relay's own address, however it is written.
    func testTheIPv4LoopbackIsThisMac() {
        XCTAssertTrue(HubPeer.isLoopback(peer(.ipv4(.loopback))))
        XCTAssertTrue(HubPeer.isLoopback(peer(.ipv4(IPv4Address("127.0.0.1")!))))
        XCTAssertTrue(HubPeer.isLoopback(peer("127.0.0.1")))
    }

    /// The IPv6 loopback, and the IPv4 one mapped into IPv6, as a listener
    /// on both stacks may report it.
    func testTheIPv6LoopbackAndTheMappedOneAreThisMac() {
        XCTAssertTrue(HubPeer.isLoopback(peer(.ipv6(.loopback))))
        XCTAssertTrue(HubPeer.isLoopback(peer(.ipv6(IPv6Address("::ffff:127.0.0.1")!))))
    }

    /// The clock, or anything else on the network, mapped or not.
    func testAnAddressOnTheNetworkIsNotThisMac() {
        XCTAssertFalse(HubPeer.isLoopback(peer(.ipv4(IPv4Address("192.168.1.22")!))))
        XCTAssertFalse(HubPeer.isLoopback(peer(.ipv6(IPv6Address("::ffff:192.168.1.22")!))))
        XCTAssertFalse(HubPeer.isLoopback(peer(.ipv6(IPv6Address("fe80::1")!))))
    }

    /// A name, or an endpoint that is no host and port, is not trusted.
    func testANameOrAnotherEndpointIsNotThisMac() {
        XCTAssertFalse(HubPeer.isLoopback(peer(.name("localhost", nil))))
        XCTAssertFalse(HubPeer.isLoopback(.unix(path: "/tmp/hub.sock")))
    }
}
