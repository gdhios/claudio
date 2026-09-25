import XCTest
@testable import Claudio

/// The links Claudio hands Galette. Galette reads two forms by name and
/// refuses any other, a bare « ? » included: a name has to arrive whole
/// whatever it holds — an ampersand left bare would cut the artist in two, a
/// « ? » would get the link refused.
final class GaletteLinkTests: XCTestCase {

    func testAnArtistOpensByName() {
        XCTAssertEqual(GaletteLink.artist(name: "Air").url.absoluteString,
                       "galette://artist?name=Air")
    }

    func testAnAlbumOpensByItsArtistAndItsTitle() {
        XCTAssertEqual(GaletteLink.album(artist: "Air", title: "Moon Safari").url.absoluteString,
                       "galette://album?artist=Air&title=Moon%20Safari")
    }

    /// One artist, not three: the comma, the spaces and the ampersand stay
    /// inside the name.
    func testSpacesAndAnAmpersandStayInsideTheName() {
        XCTAssertEqual(GaletteLink.artist(name: "Earth, Wind & Fire").url.absoluteString,
                       "galette://artist?name=Earth%2C%20Wind%20%26%20Fire")
    }

    /// What `URLComponents` would leave bare in a value: Galette refuses a
    /// bare « ? », and « = » or « # » would end the value early.
    func testTheQuerysOwnPunctuationIsEncoded() {
        XCTAssertEqual(GaletteLink.encoded("C+C Music Factory"), "C%2BC%20Music%20Factory")
        XCTAssertEqual(GaletteLink.encoded("#1 Crush"), "%231%20Crush")
        XCTAssertEqual(GaletteLink.encoded("Who?"), "Who%3F")
        XCTAssertEqual(GaletteLink.encoded("a=b"), "a%3Db")
    }

    func testJapaneseAndAccentsGoAsUTF8() {
        XCTAssertEqual(GaletteLink.encoded("間宮貴子"), "%E9%96%93%E5%AE%AE%E8%B2%B4%E5%AD%90")
        XCTAssertEqual(GaletteLink.encoded("Beyoncé"), "Beyonc%C3%A9")
        XCTAssertEqual(GaletteLink.encoded("Sigur Rós"), "Sigur%20R%C3%B3s")
    }

    func testUnreservedCharactersStayAsTheyAre() {
        XCTAssertEqual(GaletteLink.encoded("AZaz09-._~"), "AZaz09-._~")
    }

    /// Whatever a name holds, reading the link back gives it unchanged.
    func testEveryNameComesBackWhole() throws {
        let names = ["Earth, Wind & Fire", "C+C Music Factory", "#1 Crush", "Who?", "a=b&c=d",
                     "間宮貴子", "Sigur Rós", "100% Pure", "AC/DC"]
        for name in names {
            let link = GaletteLink.album(artist: name, title: name)
            let items = try XCTUnwrap(URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.map(\.name), ["artist", "title"], name)
            XCTAssertEqual(items.map(\.value), [name, name], name)
        }
    }
}
