import XCTest
@testable import Claudio

/// Claudio's face on several clocks: one bridge per clock with the face
/// ticked, started when a clock comes or moves, stopped when it goes or
/// loses the face, and left alone otherwise, since a bridge that starts
/// again installs and puts the face away for nothing. The bridges are
/// `FakeFaceBridge`: no device is called.
@MainActor
final class UlanziFaceFleetTests: XCTestCase {

    private let desk = UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!)
    private let lounge = UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!)
    private var made: [FakeFaceBridge] = []
    private var statuses: [(id: UUID, status: UlanziBridge.Status)] = []

    private var fleet: UlanziFaceFleet!

    override func setUp() async throws {
        fleet = makeFleet()
    }

    override func tearDown() async throws {
        fleet = nil
    }

    /// A fleet that makes its bridges here, and says every status.
    private func makeFleet() -> UlanziFaceFleet {
        let fleet = UlanziFaceFleet(makeBridge: { [unowned self] address, after in
            let bridge = FakeFaceBridge(address: address, after: after)
            made.append(bridge)
            return bridge
        })
        fleet.onStatusChange = { [unowned self] in statuses.append(($0, $1)) }
        return fleet
    }

    /// The bridge made last on `address`.
    private func bridge(on address: URL) throws -> FakeFaceBridge {
        try XCTUnwrap(made.last { $0.address == address }, "no bridge on \(address)")
    }

    // MARK: - Applying the list

    /// Two clocks with the face: two bridges, each on its clock's address.
    func testTwoClocksStartTwoBridges() {
        fleet.apply([desk, lounge])

        XCTAssertEqual(made.map(\.address), [desk.address, lounge.address])
        XCTAssertEqual(made.map(\.stops), [0, 0])
    }

    /// The same list again, or a list where only a name or the flags moved:
    /// nothing starts, nothing stops.
    func testWhatDoesNotTouchTheFaceLeavesTheBridgesAlone() {
        fleet.apply([desk, lounge])

        var renamed = desk
        renamed.name = "Bureau de Guillaume"
        renamed.alerts = false
        fleet.apply([lounge, renamed])

        XCTAssertEqual(made.count, 2)
        XCTAssertEqual(made.map(\.stops), [0, 0])
    }

    /// A clock removed: its bridge stops, the other goes on.
    func testRemovingAClockStopsItsBridgeOnly() throws {
        fleet.apply([desk, lounge])

        fleet.apply([lounge])

        XCTAssertEqual(try bridge(on: desk.address).stops, 1)
        XCTAssertEqual(try bridge(on: lounge.address).stops, 0)
        XCTAssertEqual(made.count, 2)
    }

    /// A clock that moved: the bridge on the old address stops, a new one
    /// starts on the new, and the other clock's stays as it is.
    func testAClockThatMovedStartsOver() throws {
        fleet.apply([desk, lounge])
        let old = try bridge(on: lounge.address)

        var moved = lounge
        moved.address = URL(string: "http://192.168.1.42")!
        fleet.apply([desk, moved])

        XCTAssertEqual(old.stops, 1)
        XCTAssertEqual(made.count, 3)
        XCTAssertEqual(made.last?.address, moved.address)
        XCTAssertEqual(try bridge(on: desk.address).stops, 0)
    }

    /// The face unticked: that clock's bridge stops, nothing else moves.
    func testUntickingTheFaceStopsThatBridgeOnly() throws {
        fleet.apply([desk, lounge])

        var faceless = desk
        faceless.face = false
        fleet.apply([faceless, lounge])

        XCTAssertEqual(try bridge(on: desk.address).stops, 1)
        XCTAssertEqual(try bridge(on: lounge.address).stops, 0)
        XCTAssertEqual(fleet.status(of: desk.id), .off)
    }

    /// The face unticked then ticked again, or the clock back at an
    /// address it left: the bridge that starts there is handed what the
    /// one stopped there still had on its way, its off, to wait for. A
    /// bridge elsewhere waits for nothing, and the next one at that
    /// address for nothing more.
    func testABridgeStartingWhereAnotherStoppedWaitsForIt() throws {
        fleet.apply([desk, lounge])
        let off = Task<Void, Never> {}
        try bridge(on: desk.address).sending = off
        var faceless = desk
        faceless.face = false

        fleet.apply([faceless, lounge])
        fleet.apply([desk, lounge])

        XCTAssertEqual(try bridge(on: desk.address).after, [off])
        XCTAssertEqual(try bridge(on: lounge.address).after, [])

        var moved = lounge
        moved.address = URL(string: "http://192.168.1.42")!
        fleet.apply([desk, moved])
        XCTAssertEqual(made.last?.after, [])
    }

    /// A clock without the face never gets a bridge; ticking it later
    /// starts one.
    func testAClockWithoutTheFaceHasNoBridgeUntilTicked() throws {
        var faceless = desk
        faceless.face = false
        fleet.apply([faceless])
        XCTAssertTrue(made.isEmpty)

        fleet.apply([desk])
        XCTAssertEqual(try bridge(on: desk.address).stops, 0)
    }

    /// No clock at all: every bridge stops.
    func testNoClockStopsEveryBridge() {
        fleet.apply([desk, lounge])

        fleet.apply([])

        XCTAssertEqual(made.map(\.stops), [1, 1])
    }

    /// Two entries under one id, written by hand: one bridge, the first
    /// entry's.
    func testOneBridgePerClockWhateverTheList() {
        let duplicate = UlanziClock(id: desk.id, name: "Double", address: lounge.address)

        fleet.apply([desk, duplicate])

        XCTAssertEqual(made.map(\.address), [desk.address])
    }

    // MARK: - The sessions

    /// A dictation and a correction reach every bridge.
    func testTheSessionsReachEveryBridge() {
        fleet.apply([desk, lounge])
        let dictation = DictationSession(language: .frFR, model: .raw)
        let correction = CorrectionSession(request: ClaudioAction.correct.request)

        fleet.dictationSessionChanged(dictation)
        fleet.correctionSessionChanged(correction)

        for bridge in made {
            XCTAssertTrue(bridge.dictations.last.flatMap { $0 } === dictation)
            XCTAssertTrue(bridge.corrections.last.flatMap { $0 } === correction)
        }
    }

    /// A clock added mid-dictation is handed the dictation under way, so its
    /// face shows what the others show.
    func testABridgeStartedLaterIsHandedTheSessionsUnderWay() throws {
        fleet.apply([desk])
        let dictation = DictationSession(language: .frFR, model: .raw)
        fleet.dictationSessionChanged(dictation)

        fleet.apply([desk, lounge])

        let late = try bridge(on: lounge.address)
        XCTAssertTrue(late.dictations.last.flatMap { $0 } === dictation)
        XCTAssertEqual(late.corrections.count, 1)
        XCTAssertNil(late.corrections.last.flatMap { $0 })
    }

    // MARK: - Status, and the Test button

    /// Each bridge's status is read by its clock's id, and each change comes
    /// with the id; a bridge starting says where it stands at once, and one
    /// that stops says it is off.
    func testStatusesComeByClock() throws {
        fleet.apply([desk, lounge])
        XCTAssertEqual(statuses.map(\.id), [desk.id, lounge.id])
        XCTAssertEqual(statuses.map(\.status), [.installing, .installing])

        try bridge(on: lounge.address).report(.failed(.unreachable("Délai dépassé")))
        XCTAssertEqual(fleet.status(of: lounge.id), .failed(.unreachable("Délai dépassé")))
        XCTAssertEqual(fleet.status(of: desk.id), .installing)
        XCTAssertEqual(statuses.last?.id, lounge.id)

        statuses = []
        fleet.apply([lounge])
        XCTAssertEqual(statuses.map(\.id), [desk.id])
        XCTAssertEqual(statuses.map(\.status), [.off])
        XCTAssertEqual(fleet.status(of: desk.id), .off)
    }

    /// A bridge let go says nothing more under its clock's id.
    func testABridgeStoppedSaysNothingMore() throws {
        fleet.apply([desk])
        let stopped = try bridge(on: desk.address)
        fleet.apply([])
        statuses = []

        stopped.report(.ready)

        XCTAssertTrue(statuses.isEmpty)
        XCTAssertEqual(fleet.status(of: desk.id), .off)
    }

    /// "Test" smiles on the clock named, and on no other.
    func testTheTestOnlyTouchesItsClock() throws {
        fleet.apply([desk, lounge])

        fleet.test(lounge.id)
        fleet.test(UUID())

        XCTAssertEqual(try bridge(on: lounge.address).tests, 1)
        XCTAssertEqual(try bridge(on: desk.address).tests, 0)
    }

    // MARK: - Quitting

    /// Quitting lets every bridge go, and their offs go all at once: each
    /// of these two only ends once the other has started, so one after the
    /// other they would hold the quit for half the bound at least.
    func testQuittingPutsEveryFaceAwayAtOnce() {
        fleet.apply([desk, lounge])
        let log = QuitLog()
        let rendezvous = Rendezvous(count: 2)
        made[0].putAway = { await rendezvous.arrive(); log.record("Bureau") }
        made[1].putAway = { await rendezvous.arrive(); log.record("Salon") }
        let start = Date()

        fleet.prepareToQuit(within: 5)

        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertEqual(made.map(\.quits), [1, 1])
        XCTAssertEqual(Set(log.sent), ["Bureau", "Salon"])
    }

    /// A clock that doesn't answer holds the quit no longer than the bound,
    /// and keeps nobody else's off from going.
    func testQuittingWaitsNoLongerThanTheBound() {
        fleet.apply([desk, lounge])
        let log = QuitLog()
        made[0].putAway = { try? await Task.sleep(for: .seconds(30)); log.record("Bureau") }
        made[1].putAway = { log.record("Salon") }
        let start = Date()

        fleet.prepareToQuit(within: 0.2)

        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(log.sent, ["Salon"])
    }

    /// Faces that can't be up send nothing, and the app goes at once.
    func testQuittingWithNothingUpSendsNothing() {
        fleet.apply([desk, lounge])
        let start = Date()

        fleet.prepareToQuit(within: 5)

        XCTAssertEqual(made.map(\.quits), [1, 1])
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
