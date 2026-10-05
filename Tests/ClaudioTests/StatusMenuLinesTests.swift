import XCTest
@testable import Claudio

/// The three status lines at the foot of the menu bar's menu: where
/// dictation, the Ulanzi clocks and the Stream Deck stand, read at a glance
/// and one click from their tab. A line that says "ready" over a clock
/// nobody can reach sends Guillaume looking everywhere but at the fault.
final class StatusMenuLinesTests: XCTestCase {

    private let desk = UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!)
    private let lounge = UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!)

    private func row(_ clock: UlanziClock, face: UlanziBridge.Status,
                     alerts: ClaudeCodeHub.ClockStatus?) -> UlanziStatusModel.ClockRow {
        UlanziStatusModel.ClockRow(clock: clock, faceStatus: face, alertsStatus: alerts)
    }

    // MARK: - Dictation

    func testDictationNamesTheKeyToHold() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: true, key: "⌥ droite"), "Dictée : maintenir ⌥ droite")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: true, key: "Right ⌥"), "Dictation: hold Right ⌥")
    }

    /// Off is off, whatever key would dictate once it's back on.
    func testDictationSwitchedOffSaysSo() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: false, key: "⌥ droite"), "Dictée : désactivée")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: false, key: nil), "Dictation: off")
    }

    /// Both shortcuts cleared: on, and no way to start it.
    func testDictationWithoutAnyKeySaysSo() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: true, key: nil), "Dictée : aucun raccourci")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.dictation(enabled: true, key: nil), "Dictation: no shortcut")
    }

    /// The key named is the one the Shortcuts tab shows for "Dictate": its
    /// lone key, which takes the combination's place, else its combination.
    /// The other language's shortcut only when "Dictate" has neither.
    func testTheKeyIsDictatesOwnBeforeTheOtherLanguages() {
        XCTAssertEqual(StatusMenuLines.dictationKey([(loneKey: "⌥ droite", combination: ""),
                                                     (loneKey: nil, combination: "⌃⌥⌘D")]), "⌥ droite")
        XCTAssertEqual(StatusMenuLines.dictationKey([(loneKey: nil, combination: "⌃⌥⌘Espace"),
                                                     (loneKey: "⌘ droite", combination: "")]), "⌃⌥⌘Espace")
        XCTAssertEqual(StatusMenuLines.dictationKey([(loneKey: nil, combination: ""),
                                                     (loneKey: nil, combination: "⌃⌥⌘D")]), "⌃⌥⌘D")
        XCTAssertNil(StatusMenuLines.dictationKey([(loneKey: nil, combination: ""),
                                                   (loneKey: nil, combination: "")]))
    }

    // MARK: - Ulanzi

    func testNoClockSaysSo() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.ulanzi([]), "Ulanzi : aucune horloge")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.ulanzi([]), "Ulanzi: no clock")
    }

    func testClocksReadyOnEveryTickedRoleAreCounted() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .ready, alerts: .ready)]),
                       "Ulanzi : 1 horloge prête")
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .ready, alerts: .ready),
                                               row(lounge, face: .ready, alerts: .ready)]),
                       "Ulanzi : 2 horloges prêtes")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .ready, alerts: .ready)]),
                       "Ulanzi: 1 clock ready")
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .ready, alerts: .ready),
                                               row(lounge, face: .ready, alerts: .ready)]),
                       "Ulanzi: 2 clocks ready")
    }

    /// A role left unticked has nothing to be ready for: a clock that only
    /// shows the face is ready once its face is.
    func testAnUntickedRoleHoldsNoClockBack() {
        useLanguage(.french)
        let faceOnly = UlanziClock(name: "Cuisine", address: URL(string: "http://192.168.1.24")!,
                                   face: true, alerts: false)
        XCTAssertEqual(StatusMenuLines.ulanzi([row(faceOnly, face: .ready, alerts: nil)]),
                       "Ulanzi : 1 horloge prête")
    }

    /// One clock out of reach is the line: "ready" over it would hide the
    /// one thing there is to fix.
    func testAnUnreachableClockOutranksTheReadyOnes() {
        let timeout = UlanziBridge.Status.failed(.unreachable("La requête a expiré."))
        let clocks = [row(desk, face: .ready, alerts: .ready), row(lounge, face: timeout, alerts: .pending)]
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.ulanzi(clocks), "Ulanzi : 1 horloge injoignable")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.ulanzi(clocks), "Ulanzi: 1 clock unreachable")
    }

    /// Either role failing counts its clock, once; a clock that answered no
    /// counts like one that didn't answer. The tab says which.
    func testEitherRoleFailingCountsItsClockOnce() {
        let clocks = [row(desk, face: .failed(.unreachable("Hors ligne")), alerts: .unreachable("Hors ligne")),
                      row(lounge, face: .ready, alerts: .rejected("403"))]
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.ulanzi(clocks), "Ulanzi : 2 horloges injoignables")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.ulanzi(clocks), "Ulanzi: 2 clocks unreachable")
    }

    /// A face still installing, or flags not heard from yet: neither ready
    /// nor out of reach. Counted apart until they settle.
    func testAClockStillStartingIsWaiting() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .ready, alerts: .ready),
                                               row(lounge, face: .installing, alerts: .ready)]),
                       "Ulanzi : 1 horloge en attente")
        XCTAssertEqual(StatusMenuLines.ulanzi([row(desk, face: .off, alerts: .pending),
                                               row(lounge, face: .ready, alerts: .pending)]),
                       "Ulanzi : 2 horloges en attente")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.ulanzi([row(lounge, face: .installing, alerts: .ready)]),
                       "Ulanzi: 1 clock waiting")
    }

    // MARK: - Stream Deck

    func testAPluginOnTheLineIsConnected() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .connected(clients: 1), pluginInstalled: true, choice: nil),
                       "Stream Deck : connecté")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .connected(clients: 2), pluginInstalled: true, choice: nil),
                       "Stream Deck: connected")
    }

    /// The door is open and nobody came: waiting, or a bridge that should
    /// run and doesn't. Either way, not connected.
    func testAnOpenDoorWithNobodyIsNotConnected() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .waiting, pluginInstalled: true, choice: nil),
                       "Stream Deck : non connecté")
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .waiting, pluginInstalled: false, choice: true),
                       "Stream Deck : non connecté")
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: true, choice: nil),
                       "Stream Deck : non connecté")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .waiting, pluginInstalled: true, choice: nil),
                       "Stream Deck: not connected")
    }

    /// Left to itself without a plugin, the bridge stays off: what's missing
    /// is the plugin, in the tab's own words.
    func testNoPluginSaysSo() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: false, choice: nil),
                       "Stream Deck : plugin absent")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: false, choice: nil),
                       "Stream Deck: plugin not found")
    }

    /// Switched off by hand outranks the plugin, there or not.
    func testSwitchedOffSaysSo() {
        useLanguage(.french)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: true, choice: false),
                       "Stream Deck : désactivé")
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: false, choice: false),
                       "Stream Deck : désactivé")
        useLanguage(.english)
        XCTAssertEqual(StatusMenuLines.streamDeck(status: .off, pluginInstalled: true, choice: false),
                       "Stream Deck: off")
    }
}
