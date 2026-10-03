import Foundation

extension URLResponse {
    /// A 2xx, or a response with no HTTP status at all: what a lookup takes
    /// for an answer worth reading.
    var isSuccessful: Bool {
        (self as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
    }
}
