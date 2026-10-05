import XCTest
@testable import Claudio

/// What the Ulanzi tab shows, and what its cards and buttons mean. Each
/// card is a clock as typed, submitted on its own: its address read like
/// Ollama's, a bare host getting its scheme, one nobody could call leaving
/// the clock's kept address alone; the other cards neither applied nor
/// touched; the list applied only when it changed. The model stores
/// nothing and calls nothing itself (the app applies the list, runs the
/// test and the hook), so these tests touch no preference, no device and no
/// file.
@MainActor
final class UlanziStatusModelTests: XCTestCase {

    private var applied: [[UlanziClock]] = []
    private var tested: [UUID] = []
    private let desk = UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!)
    private let lounge = UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!,
                                     face: true, alerts: false)

    private func wiredModel(_ clocks: [UlanziClock] = []) -> UlanziStatusModel {
        let model = UlanziStatusModel()
        model.show(clocks)
        model.applyClocks = { [unowned self] in applied.append($0) }
        model.test = { [unowned self] in tested.append($0) }
        return model
    }

    // MARK: - What it starts with

    /// Built and left alone: no clock, the relay off, no hook.
    func testAFreshModelHasNothing() {
        let model = UlanziStatusModel()
        XCTAssertEqual(model.clocks, [])
        XCTAssertEqual(model.hub, .off)
        XCTAssertEqual(model.hook, .absent)
        XCTAssertEqual(model.drafts, [])
    }

    /// The clocks shown: the face off until its bridge says otherwise, the
    /// flags waiting when ticked, nothing to say when not.
    func testTheClocksShownStartOffOrWaiting() {
        let model = wiredModel([desk, lounge])

        XCTAssertEqual(model.clocks.map(\.clock), [desk, lounge])
        XCTAssertEqual(model.clocks.map(\.faceStatus), [.off, .off])
        XCTAssertEqual(model.clocks.map(\.alertsStatus), [.pending, nil])
    }

    /// One card per clock, its address as it is called.
    func testTheCardsAreTheClocksAsKept() {
        let model = wiredModel([desk])

        XCTAssertEqual(model.drafts, [UlanziStatusModel.ClockDraft(id: desk.id, name: "Bureau",
                                                                    address: "http://192.168.1.22",
                                                                    face: true, alerts: true)])
    }

    /// A card added: the first name free, both roles, no address yet.
    func testANewCardTakesTheFirstFreeName() {
        let model = wiredModel()

        let first = model.newDraft(among: [])
        XCTAssertEqual(first.name, "Ulanzi")
        XCTAssertEqual(first.address, "")
        XCTAssertTrue(first.face)
        XCTAssertTrue(first.alerts)
        XCTAssertEqual(model.newDraft(among: [first]).name, "Ulanzi 2")
    }

    // MARK: - Submitting a card

    /// A new card with a bare IP becomes a clock, called with its scheme,
    /// and the list is applied once.
    func testANewCardWithAnAddressBecomesAClock() throws {
        let model = wiredModel([desk])
        var card = model.newDraft(among: model.drafts)
        card.address = " 192.168.1.30 "

        XCTAssertTrue(model.submit(card.id, in: model.drafts + [card]))

        let added = try XCTUnwrap(model.clocks.last?.clock)
        XCTAssertEqual(added.id, card.id)
        XCTAssertEqual(added.name, "Ulanzi")
        XCTAssertEqual(added.address, URL(string: "http://192.168.1.30"))
        XCTAssertEqual(applied, [[desk, added]])
        XCTAssertEqual(model.clocks.last?.alertsStatus, .pending)
    }

    /// The same cards again restart nothing: the face would install and go
    /// away, the flags lose their queue, for nothing.
    func testTheSameCardsAgainApplyNothing() {
        let model = wiredModel([desk, lounge])
        var cards = model.drafts
        cards[0].address = "192.168.1.22"

        XCTAssertTrue(model.submit(desk.id, in: cards))
        XCTAssertTrue(model.submit(lounge.id, in: model.drafts))

        XCTAssertTrue(applied.isEmpty)
    }

    /// An address nobody could call doesn't replace the one that works: the
    /// clock keeps it, the card says so, and the rest of the card counts.
    func testAnUnreadableAddressKeepsTheClocksOwn() {
        let model = wiredModel([desk])
        var cards = model.drafts
        cards[0].address = "ftp://192.168.1.22"
        cards[0].name = "Bureau du haut"

        XCTAssertFalse(model.submit(desk.id, in: cards))

        XCTAssertEqual(model.clocks.first?.clock.address, desk.address)
        XCTAssertEqual(model.clocks.first?.clock.name, "Bureau du haut")
        XCTAssertEqual(model.unreadable, [desk.id])
        XCTAssertEqual(model.redrafted(cards, after: desk.id).first?.address, "http://192.168.1.22")

        XCTAssertTrue(model.submit(desk.id, in: model.drafts))
        XCTAssertEqual(model.unreadable, [])
    }

    /// A new card without an address yet is no clock, and no mistake
    /// either; one with an address nobody could call is no clock, and says
    /// so, its text left as typed.
    func testANewCardIsAClockOnceItsAddressReads() {
        let model = wiredModel([desk])
        let blank = model.newDraft(among: model.drafts)
        var typo = model.newDraft(among: model.drafts + [blank])
        typo.address = "http://"

        let cards = model.drafts + [blank, typo]

        XCTAssertTrue(model.submit(blank.id, in: cards))
        XCTAssertFalse(model.submit(typo.id, in: cards))

        XCTAssertEqual(model.clocks.map(\.clock), [desk])
        XCTAssertEqual(model.unreadable, [typo.id])
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(model.redrafted(cards, after: typo.id), cards)
    }

    /// A card removed takes its clock with it.
    func testRemovingACardRemovesItsClock() {
        let model = wiredModel([desk, lounge])

        model.remove(desk.id)

        XCTAssertEqual(applied, [[lounge]])
        XCTAssertEqual(model.clocks.map(\.clock), [lounge])
    }

    /// A role unticked is applied at once; the flags have nothing to say
    /// once unticked, the face is off.
    func testTickingARoleIsApplied() {
        let model = wiredModel([desk])
        model.faceStatusChanged(.ready, of: desk.id)
        model.alertsStatusChanged(.ready, of: desk.id)
        var cards = model.drafts
        cards[0].alerts = false

        model.submit(desk.id, in: cards)

        XCTAssertEqual(applied.last?.first?.alerts, false)
        XCTAssertNil(model.clocks.first?.alertsStatus)
        XCTAssertEqual(model.clocks.first?.faceStatus, .ready, "the face is not touched")

        cards[0].face = false
        model.submit(desk.id, in: cards)
        XCTAssertEqual(model.clocks.first?.faceStatus, .off)
    }

    /// A name left blank: a clock keeps its own, a new one gets the first
    /// free.
    func testABlankNameIsNoName() {
        let model = wiredModel([desk])
        var cards = model.drafts
        cards[0].name = "  "
        var card = model.newDraft(among: cards)
        card.name = ""
        card.address = "192.168.1.30"

        model.submit(desk.id, in: cards + [card])
        model.submit(card.id, in: cards + [card])

        XCTAssertEqual(model.clocks.map(\.clock.name), ["Bureau", "Ulanzi"])
    }

    /// Two clocks at one address are two clocks: nothing is merged.
    func testNothingIsDeduplicated() {
        let model = wiredModel([desk])
        var card = model.newDraft(among: model.drafts)
        card.address = "192.168.1.22"

        XCTAssertTrue(model.submit(card.id, in: model.drafts + [card]))

        XCTAssertEqual(model.clocks.map(\.clock.address), [desk.address, desk.address])
    }

    /// A clock whose address changed starts over: off, waiting.
    func testAClockThatMovedStartsOver() {
        let model = wiredModel([desk])
        model.faceStatusChanged(.ready, of: desk.id)
        model.alertsStatusChanged(.ready, of: desk.id)
        var cards = model.drafts
        cards[0].address = "192.168.1.40"

        model.submit(desk.id, in: cards)

        XCTAssertEqual(model.clocks.first?.faceStatus, .off)
        XCTAssertEqual(model.clocks.first?.alertsStatus, .pending)
    }

    // MARK: - One card at a time

    /// Ticking a role on the lounge's card applies the lounge alone: the
    /// address half typed on the desk's card is neither applied, nor said
    /// to be wrong, nor lost to the card shown as kept.
    func testSubmittingACardLeavesTheOthersAsTyped() {
        let model = wiredModel([desk, lounge])
        var cards = model.drafts
        cards[0].address = "192.168.1."
        cards[1].alerts = true

        XCTAssertTrue(model.submit(lounge.id, in: cards))

        var flagged = lounge
        flagged.alerts = true
        XCTAssertEqual(applied, [[desk, flagged]])
        XCTAssertEqual(model.unreadable, [])
        XCTAssertEqual(model.redrafted(cards, after: lounge.id).first?.address, "192.168.1.")
    }

    /// Removing the lounge's card keeps the desk as kept, whatever its card
    /// shows meanwhile.
    func testRemovingACardLeavesTheOthersAsKept() {
        let model = wiredModel([desk, lounge])
        var cards = model.drafts
        cards[0].address = "192.168.1.99"

        model.remove(lounge.id)

        XCTAssertEqual(applied, [[desk]])
        XCTAssertEqual(cards[0].address, "192.168.1.99")
    }

    /// Testing the desk applies nothing of the lounge's card, typed or not.
    func testTestingACardLeavesTheOthersAsTyped() {
        let model = wiredModel([desk, lounge])
        var cards = model.drafts
        cards[1].address = "192.168.1.99"
        cards[1].name = "Salon du bas"

        XCTAssertTrue(model.testTyped(desk.id, in: cards))

        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(tested, [desk.id])
        XCTAssertEqual(model.clocks.map(\.clock), [desk, lounge])
    }

    // MARK: - The Test button

    /// Its card is kept first, then the clock smiles.
    func testTestingKeepsItsCardThenTries() {
        let model = wiredModel([desk])
        var cards = model.drafts
        cards[0].address = "192.168.1.30"

        XCTAssertTrue(model.testTyped(desk.id, in: cards))

        XCTAssertEqual(applied.last?.first?.address, URL(string: "http://192.168.1.30"))
        XCTAssertEqual(tested, [desk.id])
    }

    /// An address nobody could call is reported, and the old one is not
    /// tried in its place: the clock smiling would say the typo works.
    func testTestingAnUnreadableAddressTriesNothing() {
        let model = wiredModel([desk])
        var cards = model.drafts
        cards[0].address = "ftp://192.168.1.30"

        XCTAssertFalse(model.testTyped(desk.id, in: cards))

        XCTAssertEqual(tested, [])
    }

    /// A clock without the face has no face to smile with.
    func testAClockWithoutTheFaceIsNotTested() {
        let model = wiredModel([desk])
        var cards = model.drafts
        cards[0].face = false

        model.testTyped(desk.id, in: cards)

        XCTAssertEqual(tested, [])
    }

    /// A model nobody wired, a preview's, takes the list and asks nothing
    /// of an app that isn't there.
    func testAModelWithNoAppBehindItStillTakesTheList() {
        let model = UlanziStatusModel()
        var card = model.newDraft(among: [])
        card.address = "192.168.1.30"

        XCTAssertTrue(model.submit(card.id, in: [card]))
        XCTAssertTrue(model.testTyped(card.id, in: model.drafts))
        XCTAssertEqual(model.clocks.first?.clock.address, URL(string: "http://192.168.1.30"))
    }

    // MARK: - What the app reports

    /// Each status lands on its clock's row, and on no other; a clock
    /// unknown, or a role unticked, takes none.
    func testStatusesLandOnTheirClock() {
        let model = wiredModel([desk, lounge])

        model.faceStatusChanged(.installing, of: lounge.id)
        model.alertsStatusChanged(.unreachable("Délai dépassé"), of: desk.id)
        model.alertsStatusChanged(.ready, of: lounge.id)
        model.faceStatusChanged(.ready, of: UUID())

        XCTAssertEqual(model.clocks.map(\.faceStatus), [.off, .installing])
        XCTAssertEqual(model.clocks.map(\.alertsStatus), [.unreachable("Délai dépassé"), nil])
    }

    /// The hook read again as Settings comes up: where it stands now, and
    /// the failure of an earlier try forgotten, fixed by hand since or not.
    func testTheHookReadAgainForgetsAnEarlierFailure() {
        let model = UlanziStatusModel()
        model.hookFailure = "Permission denied"

        model.hookRead(.installed)

        XCTAssertEqual(model.hook, .installed)
        XCTAssertNil(model.hookFailure)
    }

    // MARK: - The lines

    /// The face's line: out of reach and in error are two things to fix, a
    /// cable or an address against a clock that answered no.
    func testTheFaceLineSaysWhatWentWrong() {
        useLanguage(.french)
        let lines: [(UlanziBridge.Status, String)] = [
            (.off, "Désactivé"),
            (.installing, "Installation du visage…"),
            (.ready, "Prêt"),
            (.failed(.unreachable("Délai dépassé")), "Injoignable : Délai dépassé"),
            (.failed(.rejected(status: 503, message: "busy")), "Erreur : busy"),
            (.failed(.rejected(status: 503, message: "")), "Erreur : l'appareil a répondu 503"),
            (.failed(.scriptBroken("syntax_error: x")), "Erreur : syntax_error: x"),
        ]
        for (status, line) in lines {
            XCTAssertEqual(UlanziStatusModel.faceLine(status), line)
        }
    }

    /// The flags' line, a clock at a time.
    func testTheFlagsLine() {
        useLanguage(.french)
        XCTAssertEqual(UlanziStatusModel.alertsLine(.pending), "En attente")
        XCTAssertEqual(UlanziStatusModel.alertsLine(.ready), "Prêt")
        XCTAssertEqual(UlanziStatusModel.alertsLine(.unreachable("Délai dépassé")), "Injoignable : Délai dépassé")
        XCTAssertEqual(UlanziStatusModel.alertsLine(.rejected("busy")), "Refusé : busy")
    }

    /// The relay's door, and the hook.
    func testTheRelayAndHookLines() {
        useLanguage(.french)
        let model = UlanziStatusModel()
        XCTAssertEqual(model.hubLine, "Désactivé : aucune horloge avec les fanions")
        model.hub = .listening(port: 50678)
        XCTAssertEqual(model.hubLine, "À l'écoute sur le port 50678")
        model.hub = .failed("Adresse déjà utilisée")
        XCTAssertEqual(model.hubLine, "Erreur : Adresse déjà utilisée")

        XCTAssertEqual(model.hookLine, "Hook absent")
        model.hook = .installed
        XCTAssertEqual(model.hookLine, "Hook installé dans Claude Code")
        model.hook = .unreadable("Unexpected end of file")
        XCTAssertEqual(model.hookLine, "Réglages Claude Code illisibles : Unexpected end of file")
        model.hook = .noRelay
        XCTAssertEqual(model.hookLine, "Relais absent de cette version")
    }

    /// The same lines in English.
    func testTheLinesInEnglish() {
        useLanguage(.english)
        let model = UlanziStatusModel()
        XCTAssertEqual(UlanziStatusModel.faceLine(.failed(.unreachable("Timed out"))), "Unreachable: Timed out")
        XCTAssertEqual(UlanziStatusModel.faceLine(.failed(.scriptBroken("syntax_error: x"))), "Error: syntax_error: x")
        XCTAssertEqual(UlanziStatusModel.alertsLine(.pending), "Waiting")
        XCTAssertEqual(UlanziStatusModel.alertsLine(.rejected("busy")), "Refused: busy")
        XCTAssertEqual(model.hubLine, "Off: no clock with the flags")
        model.hub = .listening(port: 50678)
        XCTAssertEqual(model.hubLine, "Listening on port 50678")
        XCTAssertEqual(model.hookLine, "Hook not installed")
        model.hook = .installed
        XCTAssertEqual(model.hookLine, "Hook installed in Claude Code")
    }
}
