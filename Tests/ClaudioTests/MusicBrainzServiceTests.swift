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
    private let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP")

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        transport = FakeTransport(clock: clock)
        cache = TrackFactsCache(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudioTests.service.\(UUID().uuidString).json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.fileURL)
        super.tearDown()
    }

    private func makeService() -> MusicBrainzService {
        MusicBrainzService(transport: transport.send, version: "1.13.0", cache: cache,
                           now: { [clock] in clock!.now },
                           sleep: { [clock] duration in clock!.advance(by: duration) })
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
    /// the search already gave are kept rather than lost to the budget.
    func testPastTheBudgetTheReleaseGroupIsNotWaitedFor() async {
        transport.answers["/ws/2/recording"] = MusicBrainzLookupTests.search
        transport.answers["/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb"] = MusicBrainzLookupTests.releaseGroup
        transport.delayBeforeAnswering = 5.5  // the search alone eats the budget
        let service = makeService()

        let facts = await service.facts(for: track)
        XCTAssertEqual(facts?.releaseGroupID, "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb")
        XCTAssertEqual(transport.requests.count, 1, "no time left for the release group")
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
