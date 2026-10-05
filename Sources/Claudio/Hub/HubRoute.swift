import Foundation

/// The two ways into the hub, each ending in the launch's token: a Claude
/// Code hook's event, posted by the relay on this Mac, and a button the
/// Ulanzi reports from the local network.
enum HubRoute: Equatable {
    case hookEvent(Data)
    case button(Data)

    /// The route `method` and `path` name with `token`, carrying `body` on.
    /// nil for anything else, a wrong token included: nothing says a path
    /// exists.
    static func match(method: String, path: String, token: String, body: Data) -> HubRoute? {
        guard method == "POST", !token.isEmpty else { return nil }
        if let sent = remainder(of: path, after: "/claude-code/"), sent.isEqualInConstantTime(to: token) {
            return .hookEvent(body)
        }
        if let sent = remainder(of: path, after: "/ulanzi/button/"), sent.isEqualInConstantTime(to: token) {
            return .button(body)
        }
        return nil
    }

    /// What the hub answers `request`, and the route it hands on. 404 for no
    /// route, and for a hook event from anywhere but this Mac: the relay
    /// posts from the loopback, and the token can be read off the clock by
    /// anyone on the network. 400 for a route whose body is no JSON object,
    /// which goes no further. 200 otherwise.
    static func answer(_ request: HubRequest, token: String,
                       fromLoopback: Bool) -> (status: Int, route: HubRoute?) {
        guard let route = match(method: request.method, path: request.path, token: token, body: request.body) else {
            return (404, nil)
        }
        if case .hookEvent = route, !fromLoopback { return (404, nil) }
        guard (try? JSONSerialization.jsonObject(with: request.body)) is [String: Any] else { return (400, nil) }
        return (200, route)
    }

    private static func remainder(of path: String, after prefix: String) -> String? {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }
}
