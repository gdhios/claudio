import Foundation

/// One HTTP/1.1 request to the hub, read as a value: the request line, the
/// headers up to the blank line, then `Content-Length` bytes of body.
/// Nothing more of HTTP is needed: the relay and the clock each send one
/// small request, and the connection closes behind the answer.
struct HubRequest: Equatable {
    let method: String
    /// The request's target, without its query.
    let path: String
    let body: Data

    /// How far the bytes received so far go.
    enum Reading: Equatable {
        case complete(HubRequest)
        /// Not all there yet: more bytes may make it whole.
        case incomplete
        /// No HTTP/1 request, whatever comes next.
        case malformed
    }

    /// The request in `data` once it is all there; nil before, and for
    /// anything that isn't one.
    static func parse(_ data: Data) -> HubRequest? {
        guard case .complete(let request) = read(data) else { return nil }
        return request
    }

    static func read(_ received: Data) -> Reading {
        let data = Data(received)  // indexed from zero, whatever slice came in
        guard let blank = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: data[..<blank.lowerBound], encoding: .utf8) else { return .malformed }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard start.count == 3, !start[0].isEmpty, start[1].hasPrefix("/"), start[2].hasPrefix("HTTP/1.") else {
            return .malformed
        }
        var length = 0
        for header in lines.dropFirst() {
            guard let colon = header.firstIndex(of: ":") else { return .malformed }
            let name = header[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == "content-length" else { continue }
            let value = header[header.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let declared = Int(value), declared >= 0 else { return .malformed }
            length = declared
        }
        let bodyStart = blank.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        return .complete(HubRequest(method: String(start[0]),
                                    path: String(start[1].prefix { $0 != "?" }),
                                    body: Data(data[bodyStart..<bodyStart + length])))
    }
}
