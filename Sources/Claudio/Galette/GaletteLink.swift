import Foundation

/// A link into Galette, the music catalogue app, by name: Claudio knows a
/// track by what its player says, never by an identifier. Galette reads
/// these two forms and refuses any other.
enum GaletteLink: Hashable {
    /// `galette://artist?name=…`: the artist's catalogue when Galette follows
    /// them, a search filled in and run when it doesn't.
    case artist(name: String)
    /// `galette://album?artist=…&title=…`: the album's page when Galette finds
    /// it at that artist, what the artist's link opens otherwise.
    case album(artist: String, title: String)

    var url: URL {
        let path: String
        switch self {
        case .artist(let name):
            path = "artist?name=\(Self.encoded(name))"
        case .album(let artist, let title):
            path = "album?artist=\(Self.encoded(artist))&title=\(Self.encoded(title))"
        }
        // Fixed parts, unreserved characters and escapes: nothing in it that
        // `URL` could refuse.
        return URL(string: "galette://" + path)!
    }

    /// A value as Galette must receive it: the unreserved characters of RFC
    /// 3986 as they are, every other byte of its UTF-8 percent-encoded. Not
    /// `URLComponents`, which leaves « ? » and « + » bare in a query value —
    /// and Galette refuses a bare « ? ».
    static func encoded(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            if unreserved.contains(byte) {
                encoded.append(Character(Unicode.Scalar(byte)))
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }

    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
}
