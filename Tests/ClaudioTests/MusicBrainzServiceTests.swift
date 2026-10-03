import XCTest
@testable import Claudio

/// The service that asks MusicBrainz about a track, under its rules and the
/// panel's budget: the cache first, then the search, then the release
/// group, each on its own cadence, and nothing past six seconds. Time is
/// injected: the clock moves when the service sleeps.
final class MusicBrainzServiceTests: XCTestCase {

    private var clock: FakeClock!
    private var transport: FakeTransport!
    private var cache: TrackFactsCache!
    private var artists: ArtistFactsCache!
    private let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP")

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        transport = FakeTransport(clock: clock)
        cache = TrackFactsCache(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudioTests.service.\(UUID().uuidString).json"))
        artists = ArtistFactsCache(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudioTests.service.artists.\(UUID().uuidString).json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.fileURL)
        try? FileManager.default.removeItem(at: artists.fileURL)
        super.tearDown()
    }

    private func makeService() -> MusicBrainzService {
        MusicBrainzService(transport: transport.send, version: "1.13.0", cache: cache, artists: artists,
                           now: { [clock] in clock!.now },
                           sleep: { [clock] duration in clock!.advance(by: duration) })
    }

    // MARK: - Deezer, behind MusicBrainz

    private let recent = NowPlayingTrack(title: "Breath Meditation", artist: "Benjamin Adamson", album: "Holding Space")

    /// MusicBrainz has nothing, the player named the album: Deezer is
    /// asked, in two requests, and its facts are cached like the others.
    func testWhenMusicBrainzHasNothingDeezerIsAsked() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = DeezerLookupTests.search
        transport.answers["/album/1001749391"] = DeezerLookupTests.album
        let service = makeService()

        let facts = await service.facts(for: recent)
        XCTAssertEqual(facts?.firstReleaseDate, "2026-09-30")
        XCTAssertEqual(facts?.origin, .deezer)
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/ws/2/recording", "/search/album", "/album/1001749391"])
        XCTAssertEqual(cache.lookup(recent, now: clock.now), .facts(facts!))
    }

    /// Deezer isn't MusicBrainz: its questions go at once, outside
    /// MusicBrainz's one-a-second cadence, and don't count in it.
    func testDeezerIsNotHeldToMusicBrainzsCadence() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = DeezerLookupTests.search
        transport.answers["/album/1001749391"] = DeezerLookupTests.album
        transport.delayBeforeAnswering = 0.3
        let service = makeService()

        _ = await service.facts(for: recent)
        let sent = transport.sentAt.map { $0.timeIntervalSince(transport.sentAt[0]) }
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[1], 0.3, accuracy: 0.001, "Deezer's search goes as soon as MusicBrainz answered")
        XCTAssertEqual(sent[2], 0.6, accuracy: 0.001, "and its record as soon as the search did")

        _ = await service.artist(for: MusicSubject(kind: .artist, artist: "Benjamin Adamson", mbid: artistID))
        XCTAssertEqual(transport.sentAt[3].timeIntervalSince(transport.sentAt[0]), 1.1, accuracy: 0.001,
                       "MusicBrainz's next question counts from its own last one")
    }

    /// Without an album from the player there is nothing to ask Deezer
    /// for; and a track MusicBrainz knows never reaches Deezer.
    func testDeezerIsNotAskedWithoutAnAlbumNorBehindAMatch() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = DeezerLookupTests.search
        let service = makeService()
        _ = await service.facts(for: NowPlayingTrack(title: "Breath Meditation", artist: "Benjamin Adamson"))
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/ws/2/recording"])

        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        transport.answers["/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"] = MusicBrainzLookupTests.releaseGroup
        _ = await service.facts(for: track)
        XCTAssertFalse(transport.requests.map(\.url?.path).contains("/search/album"))
    }

    /// Both bases answered and neither knew: a miss, kept. Deezer failed:
    /// nothing is kept, the next listen asks again.
    func testAMissNeedsBothBasesToHaveAnswered() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = #"{"data":[],"total":0}"#
        let service = makeService()
        let missed = await service.facts(for: recent)
        XCTAssertNil(missed)
        XCTAssertEqual(cache.lookup(recent, now: clock.now), .miss)

        let other = NowPlayingTrack(title: "Hope Radio", artist: "Benjamin Adamson", album: "Elsewhere")
        transport.answers["/search/album"] = nil
        transport.status = 503
        let failed = await service.facts(for: other)
        XCTAssertNil(failed)
        XCTAssertEqual(cache.lookup(other, now: clock.now), .unknown)
    }

    /// Deezer found the album but its record never came: that is a
    /// failure, not a miss, and nothing is kept.
    func testADeezerRecordThatFailsIsNoMiss() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = DeezerLookupTests.search
        let service = makeService()  // the album's record answers 404

        let facts = await service.facts(for: recent)
        XCTAssertNil(facts)
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/ws/2/recording", "/search/album", "/album/1001749391"])
        XCTAssertEqual(cache.lookup(recent, now: clock.now), .unknown)
    }

    // MARK: - The artist, before the long text

    private let artistID = "0df6d50f-7e43-4c6a-8220-61932b67c9c5"

    /// With the artist's id in hand: their record, then their release
    /// groups; no search. The result is kept under the artist's id.
    func testAKnownArtistIsLookedUpThenBrowsed() async {
        transport.answers["/ws/2/artist/\(artistID)"] = ArtistFactsTests.artistLookup
        transport.answers["/ws/2/release-group"] = ArtistFactsTests.releaseGroups
        let service = makeService()
        let subject = MusicSubject(kind: .artist, artist: "The Supermen Lovers", mbid: artistID)

        let facts = await service.artist(for: subject)
        XCTAssertEqual(facts?.name, "The Supermen Lovers")
        XCTAssertEqual(facts?.releases.map(\.title), ["Starlight", "The Player", "Body Double", "Staralight 20th anniversary edition"])
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/ws/2/artist/\(artistID)", "/ws/2/release-group"])
        XCTAssertEqual(artists.lookup(subject, now: clock.now), .facts(facts!))

        _ = await service.artist(for: subject)
        XCTAssertEqual(transport.requests.count, 2, "the cache answered")
    }

    /// Two artists may share a name, never an id: a namesake known by
    /// their own id is looked up, not answered with the other's facts.
    func testANamesakeIsNotAnsweredWithTheOthersFacts() async {
        transport.answers["/ws/2/artist/\(artistID)"] = ArtistFactsTests.artistLookup
        transport.answers["/ws/2/release-group"] = ArtistFactsTests.releaseGroups
        let service = makeService()
        _ = await service.artist(for: MusicSubject(kind: .artist, artist: "The Supermen Lovers", mbid: artistID))

        let namesake = "5e1f7a2b-9c3d-4e8f-a1b2-c3d4e5f60718"
        let other = await service.artist(for: MusicSubject(kind: .artist, artist: "The Supermen Lovers", mbid: namesake))
        XCTAssertNil(other, "MusicBrainz doesn't know the namesake here")
        XCTAssertEqual(transport.requests.last?.url?.path, "/ws/2/artist/\(namesake)")
    }

    /// Without an id, the artist is searched by name — on the search
    /// index's cadence — then browsed. No match is a miss, kept.
    func testAnUnknownArtistIsSearchedByName() async {
        transport.answers["/ws/2/artist"] = ArtistFactsTests.artistSearch
        transport.answers["/ws/2/release-group"] = ArtistFactsTests.releaseGroups
        let service = makeService()

        let facts = await service.artist(for: MusicSubject(kind: .album, artist: "The Supermen Lovers", title: "The Player"))
        XCTAssertEqual(facts?.artistID, artistID)
        XCTAssertEqual(facts?.releases.count, 4)
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/ws/2/artist", "/ws/2/release-group"])

        transport.answers["/ws/2/artist"] = #"{"count":0,"offset":0,"artists":[]}"#
        let nobody = MusicSubject(kind: .artist, artist: "Nobody")
        let missed = await service.artist(for: nobody)
        XCTAssertNil(missed)
        XCTAssertEqual(artists.lookup(nobody, now: clock.now), .miss)
        XCTAssertGreaterThanOrEqual(transport.sentAt[2].timeIntervalSince(transport.sentAt[0]), 4,
                                    "two searches keep the index's cadence")
    }

    /// The long text waits for the facts, so the budget is wider than the
    /// card's; past it, the artist without their releases is still worth
    /// handing over.
    func testTheArtistsBudgetIsTenSeconds() async {
        XCTAssertEqual(MusicBrainzService.artistBudget, 10)
        transport.answers["/ws/2/artist/\(artistID)"] = ArtistFactsTests.artistLookup
        transport.answers["/ws/2/release-group"] = ArtistFactsTests.releaseGroups
        transport.delayBeforeAnswering = 9.5
        let service = makeService()
        let facts = await service.artist(for: MusicSubject(kind: .artist, artist: "The Supermen Lovers", mbid: artistID))
        XCTAssertEqual(facts?.name, "The Supermen Lovers")
        XCTAssertEqual(facts?.releases, [])
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// Two questions, in order, both signed; the facts are kept.
    func testASearchThenTheReleaseGroupGiveTheFactsAndFillTheCache() async {
        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        transport.answers["/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"] = MusicBrainzLookupTests.releaseGroup
        let service = makeService()

        let facts = await service.facts(for: track)
        XCTAssertEqual(facts?.albumTitle, "LOVE TRIP")
        XCTAssertEqual(facts?.firstReleaseDate, "1982-11-25")
        XCTAssertEqual(transport.requests.map(\.url?.path),
                       ["/ws/2/recording", "/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "User-Agent"),
                       "Claudio/1.13.0 ( https://github.com/gdhios/claudio )")
        XCTAssertEqual(cache.lookup(track, now: clock.now), .facts(facts!))

        // Asked again: the cache answers, the service asks nothing.
        _ = await service.facts(for: track)
        XCTAssertEqual(transport.requests.count, 2)
    }

    /// The search index wants four seconds between searches, the service
    /// 1.1 s between any two requests: the second track waits its turn.
    func testRequestsKeepTheServicesCadence() async {
        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        transport.answers["/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"] = MusicBrainzLookupTests.releaseGroup
        let service = makeService()

        _ = await service.facts(for: track)
        XCTAssertEqual(transport.sentAt.count, 2)
        XCTAssertGreaterThanOrEqual(transport.sentAt[1].timeIntervalSince(transport.sentAt[0]), 1.1)

        let other = NowPlayingTrack(title: "Other", artist: "間宮貴子")
        _ = await service.facts(for: other)
        XCTAssertEqual(transport.sentAt.count, 4)
        XCTAssertGreaterThanOrEqual(transport.sentAt[2].timeIntervalSince(transport.sentAt[0]), 4)
    }

    /// No match is a miss, kept a week; a failure is nothing, kept nowhere:
    /// the next listen may find the service back.
    func testAMissIsCachedButAFailureIsNot() async {
        transport.answers["/ws/2/recording"] = #"{"count":0,"offset":0,"recordings":[]}"#
        transport.answers["/search/album"] = #"{"data":[],"total":0}"#  // Deezer, asked behind, knows nothing either
        let service = makeService()
        let missed = await service.facts(for: track)
        XCTAssertNil(missed)
        XCTAssertEqual(cache.lookup(track, now: clock.now), .miss)

        let failing = NowPlayingTrack(title: "Fails", artist: "X")
        transport.answers["/ws/2/recording"] = nil
        transport.status = 503
        let failed = await service.facts(for: failing)
        XCTAssertNil(failed)
        XCTAssertEqual(cache.lookup(failing, now: clock.now), .unknown)
    }

    /// The budget: a service that takes its time is left to it. The facts
    /// the search already gave are shown rather than lost to the budget,
    /// but not kept: the next listen asks for the release group again.
    func testPastTheBudgetTheReleaseGroupIsNotWaitedFor() async {
        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        transport.answers["/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"] = MusicBrainzLookupTests.releaseGroup
        transport.delayBeforeAnswering = 5.5  // the search alone eats the budget
        let service = makeService()

        let facts = await service.facts(for: track)
        XCTAssertEqual(facts?.releaseGroupID, "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb")
        XCTAssertEqual(transport.requests.count, 1, "no time left for the release group")
        XCTAssertEqual(cache.lookup(track, now: clock.now), .unknown)
    }

    /// The release group failed: the search's guess is shown, never kept
    /// for three months in place of the record's own facts.
    func testAReleaseGroupThatFailsLeavesNothingKept() async {
        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        let service = makeService()  // the release group answers 404

        let facts = await service.facts(for: track)
        XCTAssertEqual(facts?.releaseGroupID, "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(cache.lookup(track, now: clock.now), .unknown)
    }
}

/// A clock the service moves by sleeping.
final class FakeClock: @unchecked Sendable {
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(by duration: Duration) {
        now = now.addingTimeInterval(Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18)
    }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Answers by URL path, records what was asked and when (on the fake clock).
final class FakeTransport: @unchecked Sendable {
    var answers: [String: String] = [:]
    var status = 200
    var delayBeforeAnswering: TimeInterval = 0
    private(set) var requests: [URLRequest] = []
    private(set) var sentAt: [Date] = []
    private let clock: FakeClock

    init(clock: FakeClock) { self.clock = clock }

    @Sendable
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        sentAt.append(clock.now)
        if delayBeforeAnswering > 0 { clock.advance(by: delayBeforeAnswering) }
        let path = request.url?.path ?? ""
        guard let body = answers[path] else {
            let response = HTTPURLResponse(url: request.url!, statusCode: status == 200 ? 404 : status,
                                           httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
