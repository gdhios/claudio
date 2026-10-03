import XCTest
@testable import Claudio

/// The `claudio://` links the app answers: a tab of Settings, and a music
/// subject from Galette. That is the point of parsing them as values: a
/// link that says nothing Claudio knows opens nothing at all, rather than a
/// window at random. Nothing here is a URL the system would hand to another
/// app: the scheme is Claudio's own.
final class ClaudioURLTests: XCTestCase {

    private func parse(_ string: String) -> ClaudioURL? {
        guard let url = URL(string: string) else {
            XCTFail("not a URL: \(string)")
            return nil
        }
        return ClaudioURL.parse(url)
    }

    // MARK: - "Tell me more", from Galette

    /// `claudio://music?kind=album&artist=…&title=…`: Galette's "Tell me
    /// more", with the facts it has and only them.
    func testAnAlbumLinkCarriesItsFacts() {
        let link = parse("claudio://music?kind=album&artist=%E9%96%93%E5%AE%AE%E8%B2%B4%E5%AD%90&title=LOVE%20TRIP"
                         + "&mbid=3b03f2df-1fc0&date=1982-11-25&type=Album&label=Columbia&country=JP")
        XCTAssertEqual(link, .music(MusicSubject(kind: .album, artist: "間宮貴子", title: "LOVE TRIP",
                                                 mbid: "3b03f2df-1fc0", firstReleaseDate: "1982-11-25",
                                                 type: "Album", label: "Columbia", country: "JP")))
    }

    func testAnArtistLinkNeedsOnlyTheArtist() {
        XCTAssertEqual(parse("claudio://music?kind=artist&artist=Takako%20Mamiya&mbid=abc"),
                       .music(MusicSubject(kind: .artist, artist: "Takako Mamiya", mbid: "abc")))
    }

    /// Half a subject is no subject: an album without a title, a link
    /// without an artist, a kind Claudio doesn't know.
    func testAnIncompleteMusicLinkOpensNothing() {
        XCTAssertNil(parse("claudio://music?kind=album&artist=Takako%20Mamiya"))
        XCTAssertNil(parse("claudio://music?kind=album&title=LOVE%20TRIP"))
        // A link names an album or an artist; the track is the card's own.
        XCTAssertNil(parse("claudio://music?kind=track&artist=Takako%20Mamiya&title=LOVE%20TRIP"))
        XCTAssertNil(parse("claudio://music?kind=playlist&artist=X&title=Y"))
        XCTAssertNil(parse("claudio://music"))
    }

    /// Typed by hand, or capitalized by whatever passed it on: the section
    /// is matched whatever its case. The plugin and the website hand out
    /// the first one, straight to the tab where the bridge is switched on.
    func testTheSectionIsMatchedWhateverItsCase() {
        XCTAssertEqual(parse("claudio://settings/streamdeck"), .settings(.streamDeck))
        XCTAssertEqual(parse("claudio://settings/STREAMDECK"), .settings(.streamDeck))
    }

    /// Every section of Settings is reachable, by its stored name.
    func testEverySectionIsReachableByName() {
        for section in SettingsSection.allCases {
            XCTAssertEqual(parse("claudio://settings/\(section.rawValue)"), .settings(section))
        }
    }

    /// No section named: Settings opens where it always opens.
    func testSettingsWithNoSectionOpensTheGeneralOne() {
        XCTAssertEqual(parse("claudio://settings"), .settings(.general))
    }

    /// A tab that doesn't exist — a typo, or a link from a later version:
    /// better nothing than the wrong tab.
    func testAnUnknownSectionOpensNothing() {
        XCTAssertNil(parse("claudio://settings/nope"))
    }

    /// Claudio's own scheme, and no other: a web address is the browser's
    /// business, even when it points at Claudio's site.
    func testAnotherSchemeOpensNothing() {
        XCTAssertNil(parse("https://claudio.okonoma.com/#streamdeck"))
    }

    /// The scheme is ours, the rest isn't understood: nothing opens.
    func testAnUnknownLinkOpensNothing() {
        XCTAssertNil(parse("claudio://other"))
    }
}
