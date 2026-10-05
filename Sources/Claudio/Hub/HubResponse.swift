import Foundation

/// The hub's answer on the wire: always short, in JSON for whoever reads it
/// with curl, and closing, since a connection carries one request.
enum HubResponse {
    static func data(status: Int) -> Data {
        let body = status == 200 ? #"{"ok":true}"# : #"{"ok":false}"#
        let head = "HTTP/1.1 \(status) \(reason(for: status))\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data((head + body).utf8)
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 413: "Content Too Large"
        default: "Error"
        }
    }
}
