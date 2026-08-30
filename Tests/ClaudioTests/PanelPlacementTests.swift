import XCTest
import AppKit
@testable import Claudio

/// Le panneau ne se pose jamais sous le pointeur.
///
/// Sinon la ligne recouverte se croit survolée à la seconde où le panneau
/// paraît : la sélection saute sur elle sans que la main ait bougé, et ⏎ lance
/// autre chose que ce qui est mis en avant — près du bas de l'écran, la
/// dernière ligne de la palette, l'action libre.
final class PanelPlacementTests: XCTestCase {
    /// Un écran 1920×1080 avec sa barre de menus : ce que voit `visibleFrame`.
    private let visible = NSRect(x: 0, y: 52, width: 1920, height: 998)
    /// La palette mesurée : neuf lignes au corps de texte normal.
    private let palette = NSSize(width: 460, height: 563)

    private func frame(pointer: NSPoint, size: NSSize) -> NSRect {
        let side = ResultPanel.preferredSide(anchor: pointer, size: size, in: visible)
        return ResultPanel.placement(anchor: pointer, size: size, in: visible, side: side)
    }

    func testLePointeurNEstJamaisSurLaPalette() {
        var y = visible.minY
        while y <= visible.maxY {
            var x = visible.minX
            while x <= visible.maxX {
                let pointer = NSPoint(x: x, y: y)
                XCTAssertFalse(NSPointInRect(pointer, frame(pointer: pointer, size: palette)),
                               "pointeur \(pointer) recouvert par la palette")
                x += 10
            }
            y += 10
        }
    }

    func testLaPaletteResteDansLEcran() {
        for pointer in [NSPoint(x: 0, y: 52), NSPoint(x: 1920, y: 1050),
                        NSPoint(x: 1900, y: 100), NSPoint(x: 20, y: 1000)] {
            let placed = frame(pointer: pointer, size: palette)
            XCTAssertTrue(visible.contains(placed), "cadre hors écran pour \(pointer)")
        }
    }

    func testSousLePointeurQuandIlYALaPlace() {
        let pointer = NSPoint(x: 400, y: 900)
        let placed = frame(pointer: pointer, size: palette)
        XCTAssertEqual(placed.maxY, pointer.y - 12, accuracy: 0.01)
        XCTAssertEqual(placed.minX, pointer.x + 12, accuracy: 0.01)
    }

    func testAuDessusQuandLaPlaceManqueDessous() {
        let pointer = NSPoint(x: 400, y: 200)
        XCTAssertTrue(ResultPanel.preferredSide(anchor: pointer, size: palette, in: visible).above)
        XCTAssertEqual(frame(pointer: pointer, size: palette).minY, pointer.y + 12, accuracy: 0.01)
    }

    /// Ni dessous ni dessus, et le bord droit ramènerait le panneau sur le
    /// curseur : il passe à gauche.
    func testAGaucheQuandIlNeTientNiDessousNiDessus() {
        let pointer = NSPoint(x: 1500, y: 550)
        let side = ResultPanel.preferredSide(anchor: pointer, size: palette, in: visible)
        XCTAssertFalse(side.above)
        XCTAssertTrue(side.left)
        XCTAssertEqual(frame(pointer: pointer, size: palette).maxX, pointer.x - 12, accuracy: 0.01)
    }

    /// Un panneau court n'a jamais besoin de basculer : il tient sous le
    /// pointeur partout, y compris pendant qu'un résultat s'écrit.
    func testLePanneauCourtResteSousLePointeur() {
        let court = NSSize(width: 460, height: 180)
        for y in stride(from: 300.0, through: 1000.0, by: 50.0) {
            let pointer = NSPoint(x: 700, y: y)
            XCTAssertFalse(ResultPanel.preferredSide(anchor: pointer, size: court, in: visible).above)
        }
    }
}

/// Le survol de la palette ne choisit qu'une fois la main en mouvement.
@MainActor
final class PaletteHoverTests: XCTestCase {
    private func palette() -> CorrectionSession {
        let session = CorrectionSession(request: .awaitingChoice, opensPalette: true)
        session.originalText = "un texte"
        session.phase = .choosingAction
        return session
    }

    func testLeSurvolSansMouvementNeChoisitRien() {
        let session = palette()
        session.armHover(at: CGPoint(x: 500, y: 400))
        XCTAssertFalse(session.acceptsHover(at: CGPoint(x: 500, y: 400)))
        XCTAssertFalse(session.acceptsHover(at: CGPoint(x: 501, y: 400)))  // tremblement
    }

    func testLeSurvolCompteUneFoisLePointeurBouge() {
        let session = palette()
        session.armHover(at: CGPoint(x: 500, y: 400))
        XCTAssertTrue(session.acceptsHover(at: CGPoint(x: 500, y: 460)))
        // La main a bougé : la souris reprend son métier pour de bon.
        XCTAssertTrue(session.acceptsHover(at: CGPoint(x: 500, y: 460)))
    }

    func testLeSurvolCompteQuandRienNArmeLaGarde() {
        XCTAssertTrue(palette().acceptsHover(at: CGPoint(x: 0, y: 0)))
    }
}
