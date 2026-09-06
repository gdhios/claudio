import AppKit
import XCTest
@testable import Claudio

/// Each palette row carries its rank in large type in front of it: if typing
/// that digit doesn't launch it, the rank is lying. These tests pin down who
/// launches what, on French and American keyboards alike, and without ever
/// preventing an instruction that contains digits from being typed.
final class PaletteDigitTests: XCTestCase {

    /// The expected labels are French: the suite pins the language rather than
    /// inheriting it from the machine, otherwise it fails on an English runner
    /// (CI) and passes on a French Mac.
    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
        AppSettings.language = .french
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    // MARK: - Reading the keystroke

    func testABareDigitGivesItsRank() {
        // QWERTY: the 1 key gives "1" with nothing held.
        let touche = ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [])
        XCTAssertEqual(touche?.rank, 1)
        XCTAssertEqual(touche?.withCommand, false)
    }

    func testAzertyNeedsShiftForTheDigit() {
        // Without ⇧, the top row of an AZERTY gives "& é " '": those are
        // characters, not ranks. They must be typeable in the field.
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "&", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 19, characters: "é", modifiers: []))
        // With ⇧, the character is a real digit: it launches.
        let avecMajuscule = ResultPanel.digitKey(keyCode: 19, characters: "2", modifiers: [.shift])
        XCTAssertEqual(avecMajuscule?.rank, 2)
        XCTAssertEqual(avecMajuscule?.withCommand, false)
    }

    func testWithCommandThePhysicalPositionIsEnough() {
        // ⌘ + the 1 key on an AZERTY: the character is "&", but the key is
        // in the same place as on a QWERTY.
        let azerty = ResultPanel.digitKey(keyCode: 18, characters: "&", modifiers: [.command])
        XCTAssertEqual(azerty?.rank, 1)
        XCTAssertEqual(azerty?.withCommand, true)
        // 6 and 7 aren't adjacent in key codes: 6 is at 22.
        XCTAssertEqual(ResultPanel.digitKey(keyCode: 22, characters: "-", modifiers: [.command])?.rank, 6)
        XCTAssertEqual(ResultPanel.digitKey(keyCode: 23, characters: "(", modifiers: [.command])?.rank, 5)
    }

    func testOtherModifiersLaunchNothing() {
        // ⌥ and ⌃ compose characters: that's not a rank being requested.
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.option]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.control]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.option, .command]))
    }

    func testWhatIsNotARankIsIgnored() {
        XCTAssertNil(ResultPanel.digitKey(keyCode: 29, characters: "0", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 0, characters: "a", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 0, characters: "a", modifiers: [.command]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: nil, modifiers: []))
    }

    func testTheNumericKeypadLaunchesToo() {
        // The 5 on the keypad: a digit is still a digit.
        let pave = ResultPanel.digitKey(keyCode: 87, characters: "5", modifiers: [.numericPad])
        XCTAssertEqual(pave?.rank, 5)
        XCTAssertEqual(pave?.withCommand, false)
    }

    // MARK: - What the session does with it

    @MainActor private func palette() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.phase = .choosingAction
        return session
    }

    @MainActor
    func testABareDigitLaunchesWhenNothingIsTyped() {
        let session = palette()
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: false), 0)
        XCTAssertEqual(session.paletteIndex(forRank: 3, withCommand: false), 2)
    }

    @MainActor
    func testABareDigitGetsTypedOnceAnInstructionHasStarted() {
        let session = palette()
        session.paletteQuery = "résume en"
        // Otherwise "summarize in 3 sentences" would be impossible to type.
        XCTAssertNil(session.paletteIndex(forRank: 3, withCommand: false))
        // A leading space is enough to start an instruction with a digit.
        let echappatoire = palette()
        echappatoire.paletteQuery = " "
        XCTAssertNil(echappatoire.paletteIndex(forRank: 3, withCommand: false))
    }

    @MainActor
    func testCommandStillLaunchesWhileTyping() {
        let session = palette()
        session.paletteQuery = "trad"
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: true), 0)
    }

    @MainActor
    func testARankOutsideTheListLaunchesNothing() {
        let session = palette()
        let apres = session.paletteRows.count + 1
        XCTAssertNil(session.paletteIndex(forRank: apres, withCommand: true))
        XCTAssertNil(session.paletteIndex(forRank: apres, withCommand: false))
        // Filtered down to a single action, only rank 1 (and the free row) exists.
        session.paletteQuery = "trad ang"
        XCTAssertEqual(session.paletteRows.count, 2)
        XCTAssertNil(session.paletteIndex(forRank: 3, withCommand: true))
    }

    @MainActor
    func testOutsideThePaletteNoDigitLaunchesAnything() {
        let session = palette()
        // While reading a result, "1" must stay a character.
        session.phase = .done
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: false))
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: true))
        // While typing a free-form instruction, too.
        session.phase = .askingInstruction
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: false))
    }
}
