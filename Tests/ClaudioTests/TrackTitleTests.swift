import XCTest
@testable import Claudio

/// The title MusicBrainz is asked for, and the one a track is cached under:
/// the version tails a player adds — "- Olympic Mix", "(Radio Edit)",
/// "- Remastered 2015" — make no match in the index and no other track.
/// Found on 2026-10-03 with "Am I Wrong - Olympic Mix": nothing with the
/// tail, 32 recordings at score 100 without it.
final class TrackTitleTests: XCTestCase {

    func testVersionTailsAreDropped() {
        XCTAssertEqual(TrackTitle.plain("Am I Wrong - Olympic Mix"), "Am I Wrong")
        XCTAssertEqual(TrackTitle.plain("Am I Wrong (Olympic Mix)"), "Am I Wrong")
        XCTAssertEqual(TrackTitle.plain("Hey Jude - Remastered 2015"), "Hey Jude")
        XCTAssertEqual(TrackTitle.plain("Hey Jude [Remastered]"), "Hey Jude")
        XCTAssertEqual(TrackTitle.plain("Starlight - Radio Edit"), "Starlight")
        XCTAssertEqual(TrackTitle.plain("Starlight (feat. Mani Hoffman) - Extended Version"), "Starlight (feat. Mani Hoffman)")
        XCTAssertEqual(TrackTitle.plain("One More Time - Live"), "One More Time")
        XCTAssertEqual(TrackTitle.plain("Around the World - Mono Version"), "Around the World")
    }

    /// A dash or a parenthesis that isn't a version stays: it is the title.
    func testTheTitleItselfIsKept() {
        XCTAssertEqual(TrackTitle.plain("Family Business 3D"), "Family Business 3D")
        XCTAssertEqual(TrackTitle.plain("Pop Music (That Was That)"), "Pop Music (That Was That)")
        XCTAssertEqual(TrackTitle.plain("Mix"), "Mix")
        XCTAssertEqual(TrackTitle.plain(" - Remix"), " - Remix", "nothing would be left: the title stays as given")
        XCTAssertEqual(TrackTitle.plain("真夜中のジョーク"), "真夜中のジョーク")
    }
}
