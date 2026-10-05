import Network

/// Where a connection to the hub comes from, as far as the routes care:
/// this Mac or the network. The relay posts from the loopback; the clock
/// posts from its address on the local network.
enum HubPeer {
    /// Whether `endpoint` is this Mac: 127.0.0.1 or ::1, the IPv4 loopback
    /// mapped into IPv6 included, as a listener on both stacks may report
    /// it. A name is not trusted: an accepted connection always has an
    /// address.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        if case .ipv4(let address) = host { return address.isLoopback }
        if case .ipv6(let address) = host { return address.isLoopback || address.asIPv4?.isLoopback == true }
        return false
    }
}
