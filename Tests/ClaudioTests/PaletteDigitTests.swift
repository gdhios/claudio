import AppKit
import XCTest
@testable import Claudio

/// Chaque ligne de la palette porte son rang en gros devant elle : si taper ce
/// chiffre ne la lance pas, le rang ment. Ces tests fixent qui lance quoi — au
/// clavier français comme américain, et sans jamais empêcher d'écrire une
/// consigne qui contient des chiffres.
final class PaletteDigitTests: XCTestCase {

    // MARK: - Lecture de la frappe

    func testChiffreNuDonneSonRang() {
        // QWERTY : la touche du 1 donne « 1 » sans rien tenir.
        let touche = ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [])
        XCTAssertEqual(touche?.rank, 1)
        XCTAssertEqual(touche?.withCommand, false)
    }

    func testAzertyDemandeMajusculePourLeChiffre() {
        // Sans ⇧, la rangée du haut d'un AZERTY donne « & é " ' » : ce sont des
        // caractères, pas des rangs. Ils doivent s'écrire dans le champ.
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "&", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 19, characters: "é", modifiers: []))
        // Avec ⇧, le caractère est un vrai chiffre : il lance.
        let avecMajuscule = ResultPanel.digitKey(keyCode: 19, characters: "2", modifiers: [.shift])
        XCTAssertEqual(avecMajuscule?.rank, 2)
        XCTAssertEqual(avecMajuscule?.withCommand, false)
    }

    func testAvecCommandeLaPositionPhysiqueSuffit() {
        // ⌘ + la touche du 1 sur un AZERTY : le caractère est « & », mais la
        // touche est au même endroit qu'un QWERTY.
        let azerty = ResultPanel.digitKey(keyCode: 18, characters: "&", modifiers: [.command])
        XCTAssertEqual(azerty?.rank, 1)
        XCTAssertEqual(azerty?.withCommand, true)
        // 6 et 7 ne se suivent pas dans les codes de touches : le 6 est en 22.
        XCTAssertEqual(ResultPanel.digitKey(keyCode: 22, characters: "-", modifiers: [.command])?.rank, 6)
        XCTAssertEqual(ResultPanel.digitKey(keyCode: 23, characters: "(", modifiers: [.command])?.rank, 5)
    }

    func testLesAutresModificateursNeLancentRien() {
        // ⌥ et ⌃ composent des caractères : ce n'est pas un rang qu'on demande.
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.option]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.control]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: "1", modifiers: [.option, .command]))
    }

    func testCeQuiNEstPasUnRangEstIgnore() {
        XCTAssertNil(ResultPanel.digitKey(keyCode: 29, characters: "0", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 0, characters: "a", modifiers: []))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 0, characters: "a", modifiers: [.command]))
        XCTAssertNil(ResultPanel.digitKey(keyCode: 18, characters: nil, modifiers: []))
    }

    func testPaveNumeriqueLanceAussi() {
        // Le 5 du pavé : un chiffre reste un chiffre.
        let pave = ResultPanel.digitKey(keyCode: 87, characters: "5", modifiers: [.numericPad])
        XCTAssertEqual(pave?.rank, 5)
        XCTAssertEqual(pave?.withCommand, false)
    }

    // MARK: - Ce que la session en fait

    @MainActor private func palette() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.phase = .choosingAction
        return session
    }

    @MainActor
    func testChiffreNuLanceQuandRienNEstEcrit() {
        let session = palette()
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: false), 0)
        XCTAssertEqual(session.paletteIndex(forRank: 3, withCommand: false), 2)
    }

    @MainActor
    func testChiffreNuSEcritDesQuUneConsigneCommence() {
        let session = palette()
        session.paletteQuery = "résume en"
        // Sinon « résume en 3 phrases » serait impossible à écrire.
        XCTAssertNil(session.paletteIndex(forRank: 3, withCommand: false))
        // Une espace en tête suffit à commencer une consigne par un chiffre.
        let echappatoire = palette()
        echappatoire.paletteQuery = " "
        XCTAssertNil(echappatoire.paletteIndex(forRank: 3, withCommand: false))
    }

    @MainActor
    func testCommandeLanceMemePendantLaSaisie() {
        let session = palette()
        session.paletteQuery = "trad"
        XCTAssertEqual(session.paletteIndex(forRank: 1, withCommand: true), 0)
    }

    @MainActor
    func testRangHorsListeNeLanceRien() {
        let session = palette()
        let apres = session.paletteRows.count + 1
        XCTAssertNil(session.paletteIndex(forRank: apres, withCommand: true))
        XCTAssertNil(session.paletteIndex(forRank: apres, withCommand: false))
        // Filtré à une seule action, seul le rang 1 (et la ligne libre) existe.
        session.paletteQuery = "trad ang"
        XCTAssertEqual(session.paletteRows.count, 2)
        XCTAssertNil(session.paletteIndex(forRank: 3, withCommand: true))
    }

    @MainActor
    func testHorsPaletteAucunChiffreNeLance() {
        let session = palette()
        // Pendant la lecture d'un résultat, « 1 » doit rester un caractère.
        session.phase = .done
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: false))
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: true))
        // Pendant la saisie d'une consigne libre, aussi.
        session.phase = .askingInstruction
        XCTAssertNil(session.paletteIndex(forRank: 1, withCommand: false))
    }
}
