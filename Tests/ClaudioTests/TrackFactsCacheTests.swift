import XCTest
@testable import Claudio

/// MusicBrainz is asked once per track: what it said is kept on disk under
/// the track's normalized name, a result for three months, a miss for a
/// week — the record may be added meanwhile.
final class TrackFactsCacheTests: XCTestCase {

    private var cache: TrackFactsCache!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let facts = TrackFacts(recordingID: "783dfef9", releaseGroupID: "3b03f2df",
                                   albumTitle: "LOVE TRIP", primaryType: "Album",
                                   secondaryTypes: [], firstReleaseDate: "1982-11-25")

    override func setUp() {
        super.setUp()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudioTests.facts.\(UUID().uuidString).json")
        cache = TrackFactsCache(fileURL: file)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.fileURL)
        super.tearDown()
    }

    /// Case, accents, spacing and the "(Remastered)" tail don't make
    /// another track.
    func testTheKeyForgetsCaseAccentsSpacingAndRemasterTails() {
        XCTAssertEqual(TrackFactsCache.key(title: "  Été  Indien ", artist: "JOE DASSIN"),
                       TrackFactsCache.key(title: "ete indien", artist: "joe dassin"))
        XCTAssertEqual(TrackFactsCache.key(title: "Hey Jude - Remastered 2015", artist: "The Beatles"),
                       TrackFactsCache.key(title: "Hey Jude (Remastered)", artist: "The Beatles"))
        XCTAssertEqual(TrackFactsCache.key(title: "Hey Jude", artist: "The Beatles"),
                       TrackFactsCache.key(title: "Hey Jude (Remastered)", artist: "The Beatles"))
        XCTAssertNotEqual(TrackFactsCache.key(title: "Hey Jude", artist: "The Beatles"),
                          TrackFactsCache.key(title: "Hey Jude", artist: nil))
    }

    func testUnknownThenStoredThenReadBack() {
        let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子")
        XCTAssertEqual(cache.lookup(track, now: now), .unknown)
        cache.store(facts, for: track, at: now)
        XCTAssertEqual(cache.lookup(track, now: now), .facts(facts))
        // On disk: another cache on the same file reads it.
        XCTAssertEqual(TrackFactsCache(fileURL: cache.fileURL).lookup(track, now: now), .facts(facts))
    }

    func testAResultHoldsThreeMonthsAndAMissAWeek() {
        let found = NowPlayingTrack(title: "Found", artist: "A")
        let missed = NowPlayingTrack(title: "Missed", artist: "A")
        cache.store(facts, for: found, at: now)
        cache.store(nil, for: missed, at: now)
        XCTAssertEqual(cache.lookup(missed, now: now), .miss)

        let sixDays = now.addingTimeInterval(6 * 86_400)
        XCTAssertEqual(cache.lookup(missed, now: sixDays), .miss)
        let eightDays = now.addingTimeInterval(8 * 86_400)
        XCTAssertEqual(cache.lookup(missed, now: eightDays), .unknown)

        let eightyNineDays = now.addingTimeInterval(89 * 86_400)
        XCTAssertEqual(cache.lookup(found, now: eightyNineDays), .facts(facts))
        let ninetyOneDays = now.addingTimeInterval(91 * 86_400)
        XCTAssertEqual(cache.lookup(found, now: ninetyOneDays), .unknown)
    }
}
