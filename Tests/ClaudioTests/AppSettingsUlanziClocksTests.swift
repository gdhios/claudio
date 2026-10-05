import XCTest
@testable import Claudio

/// The Ulanzi clocks Settings keeps: a list, each with its name, its address
/// and its two roles. None is the off switch: until one is added, nothing
/// about a clock is ever sent anywhere. The single address of the first
/// version becomes the first clock the first time the list is read. Each
/// test writes to throwaway defaults held in memory, never to this Mac's
/// preferences.
final class AppSettingsUlanziClocksTests: XCTestCase {

    private var defaults: UserDefaults!

    private let desk = UlanziClock(id: UUID(uuidString: "6A1D5E2C-0000-4000-8000-000000000001")!,
                                   name: "Bureau", address: URL(string: "http://192.168.1.22")!,
                                   face: true, alerts: true)
    private let lounge = UlanziClock(id: UUID(uuidString: "6A1D5E2C-0000-4000-8000-000000000002")!,
                                     name: "Salon", address: URL(string: "http://192.168.1.23")!,
                                     face: false, alerts: true)

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// The list as stored, written by hand: what another version, or a
    /// person, could leave there.
    private func store(_ json: String) {
        defaults.set(Data(json.utf8), forKey: AppSettings.ulanziClocksKey)
    }

    // MARK: - Reading and writing

    /// A fresh install has no clock: nothing is started.
    func testWithNothingStoredThereIsNoClock() {
        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [])
    }

    /// The clocks come back as they were set, in their order, every field
    /// kept.
    func testTheClocksSetAreTheClocksRead() {
        AppSettings.setUlanziClocks([desk, lounge], in: defaults)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [desk, lounge])
    }

    /// The last clock removed takes the key away rather than storing an
    /// empty list.
    func testNoClockRemovesTheKey() {
        AppSettings.setUlanziClocks([desk], in: defaults)
        AppSettings.setUlanziClocks([], in: defaults)

        XCTAssertNil(defaults.object(forKey: AppSettings.ulanziClocksKey))
        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [])
    }

    /// Stored as JSON a person can read, the address as it is called.
    func testTheListIsStoredAsJSON() throws {
        AppSettings.setUlanziClocks([desk], in: defaults)

        let data = try XCTUnwrap(defaults.data(forKey: "ulanziClocks"))
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["address"] as? String, "http://192.168.1.22")
        XCTAssertEqual(entries.first?["name"] as? String, "Bureau")
    }

    // MARK: - What can't be read

    /// An entry whose address nobody could call is left out, and the list
    /// is not written again for it: the others still work.
    func testAnEntryWithAnUnreadableAddressIsIgnoredNotRewritten() {
        let json = """
        [{"id":"6A1D5E2C-0000-4000-8000-000000000001","name":"Bureau","address":"http://192.168.1.22","face":true,"alerts":true},
         {"id":"6A1D5E2C-0000-4000-8000-000000000003","name":"Cave","address":"ftp://192.168.1.40","face":true,"alerts":false},
         {"id":"6A1D5E2C-0000-4000-8000-000000000004","name":"Grenier","address":"http://","face":true,"alerts":false}]
        """
        store(json)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [desk])
        XCTAssertEqual(defaults.data(forKey: AppSettings.ulanziClocksKey), Data(json.utf8))
    }

    /// An entry that isn't a clock at all, written by another version, is
    /// left out too.
    func testAnEntryThatIsNoClockIsIgnored() {
        store("""
        [{"name":"Sans adresse","face":true},
         {"id":"6A1D5E2C-0000-4000-8000-000000000002","name":"Salon","address":"http://192.168.1.23","face":false,"alerts":true}]
        """)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [lounge])
    }

    /// An address kept as typed, without its scheme, is read the way it
    /// will be called.
    func testAStoredBareHostIsReadOverHTTP() {
        store(#"[{"id":"6A1D5E2C-0000-4000-8000-000000000001","name":"Bureau","address":"192.168.1.22","face":true,"alerts":true}]"#)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [desk])
    }

    /// Two entries under one id, written by hand: the first counts.
    func testTheFirstEntryOfAnIdWins() {
        let other = UlanziClock(id: lounge.id, name: "Jumeau", address: lounge.address, face: true, alerts: false)
        AppSettings.setUlanziClocks([lounge, other], in: defaults)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [lounge])
    }

    /// A list that is no JSON at all is no clock, and is left where it is.
    func testAListThatCannotBeReadIsNoClock() {
        store("not json")

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [])
        XCTAssertEqual(defaults.data(forKey: AppSettings.ulanziClocksKey), Data("not json".utf8))
    }

    // MARK: - The address of the first version

    /// The one address the first version kept becomes a clock called
    /// "Ulanzi", with both roles, written in the list; the old key goes.
    func testTheSingleAddressBecomesTheFirstClock() throws {
        defaults.set("http://192.168.1.22", forKey: "ulanziURL")

        let clocks = AppSettings.ulanziClocks(in: defaults)

        let clock = try XCTUnwrap(clocks.first)
        XCTAssertEqual(clocks.count, 1)
        XCTAssertEqual(clock.name, "Ulanzi")
        XCTAssertEqual(clock.address, URL(string: "http://192.168.1.22"))
        XCTAssertTrue(clock.face)
        XCTAssertTrue(clock.alerts)
        XCTAssertNil(defaults.object(forKey: "ulanziURL"))
        XCTAssertNotNil(defaults.object(forKey: AppSettings.ulanziClocksKey))
        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), clocks, "the same clock, same id, every read")
    }

    /// Migrated once: removing that clock later doesn't bring it back.
    func testAMigratedClockRemovedStaysRemoved() {
        defaults.set("http://192.168.1.22", forKey: "ulanziURL")
        _ = AppSettings.ulanziClocks(in: defaults)

        AppSettings.setUlanziClocks([], in: defaults)

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [])
    }

    /// A list already there wins: the old address is not read.
    func testAListAlreadyThereIsNotMigratedOver() {
        AppSettings.setUlanziClocks([lounge], in: defaults)
        defaults.set("http://192.168.1.22", forKey: "ulanziURL")

        XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [lounge])
        XCTAssertEqual(defaults.string(forKey: "ulanziURL"), "http://192.168.1.22")
    }

    /// An old address nobody could call makes no clock, and writes nothing.
    func testAnUnreadableSingleAddressMakesNoClock() {
        for stored in ["", "   ", "ftp://192.168.1.22", "http://"] {
            defaults.set(stored, forKey: "ulanziURL")
            XCTAssertEqual(AppSettings.ulanziClocks(in: defaults), [], stored)
            XCTAssertNil(defaults.object(forKey: AppSettings.ulanziClocksKey), stored)
        }
    }

    // MARK: - Names

    /// "Ulanzi" for the first, then "Ulanzi 2", "Ulanzi 3": the first name
    /// no clock bears.
    func testDefaultNamesCountUp() {
        XCTAssertEqual(UlanziClock.defaultName(among: []), "Ulanzi")
        XCTAssertEqual(UlanziClock.defaultName(among: [desk]), "Ulanzi")

        var first = desk
        first.name = "Ulanzi"
        XCTAssertEqual(UlanziClock.defaultName(among: [first]), "Ulanzi 2")

        var third = lounge
        third.name = "Ulanzi 3"
        XCTAssertEqual(UlanziClock.defaultName(among: [first, third]), "Ulanzi 2")
        var second = desk
        second.name = "Ulanzi 2"
        XCTAssertEqual(UlanziClock.defaultName(among: [first, second, third]), "Ulanzi 4")
    }

    // MARK: - The contract

    /// The storage keys are part of the contract: renaming either would
    /// forget every clock set so far.
    func testTheKeysAreTheirOwn() {
        XCTAssertEqual(AppSettings.ulanziClocksKey, "ulanziClocks")
        XCTAssertEqual(AppSettings.ulanziAddressKey, "ulanziURL")
    }
}
