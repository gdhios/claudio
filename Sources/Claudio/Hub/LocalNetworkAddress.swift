import Darwin

/// The Mac's IPv4 address on the local network, where the Ulanzi reaches it
/// to report its buttons: Wi-Fi's (`en0`) first, else the first other one
/// that is up and isn't the loopback. Read from the interfaces, without
/// sending anything.
enum LocalNetworkAddress {
    struct Interface: Equatable {
        let name: String
        let address: String
        let isLoopback: Bool
        let isUp: Bool
    }

    static func current() -> String? {
        pick(from: interfaces())
    }

    static func pick(from interfaces: [Interface]) -> String? {
        let usable = interfaces.filter { $0.isUp && !$0.isLoopback }
        return (usable.first { $0.name == "en0" } ?? usable.first)?.address
    }

    /// Every IPv4 address of every interface, in the system's order.
    private static func interfaces() -> [Interface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { pointer in
            let entry = pointer.pointee
            guard let socket = entry.ifa_addr, socket.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socket, socklen_t(socket.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            let flags = Int32(entry.ifa_flags)
            return Interface(name: String(cString: entry.ifa_name),
                             address: String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)),
                                             as: UTF8.self),
                             isLoopback: flags & IFF_LOOPBACK != 0,
                             isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0)
        }
    }
}
