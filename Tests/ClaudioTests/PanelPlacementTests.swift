import XCTest
import AppKit
@testable import Claudio

/// Le panneau s'ouvre toujours au centre de l'écran actif — jamais dans un
/// coin ni débordant — et il y reste centré quand sa hauteur suit le contenu.
final class PanelCenteringTests: XCTestCase {
    /// Un écran 1920×1080 avec sa barre de menus : ce que voit `visibleFrame`.
    private let visible = NSRect(x: 0, y: 52, width: 1920, height: 998)

    func testLePanneauEstCentre() {
        let placed = ResultPanel.centered(size: NSSize(width: 460, height: 200), in: visible)
        XCTAssertEqual(placed.midX, visible.midX, accuracy: 0.01)
        XCTAssertEqual(placed.midY, visible.midY, accuracy: 0.01)
    }

    /// Chaque hauteur possible, du panneau d'accueil à la palette pleine, reste
    /// centrée au même milieu : il grandit sans glisser.
    func testLeMilieuNeBougePasQuandLaHauteurChange() {
        for height in stride(from: 180.0, through: 900.0, by: 30.0) {
            let placed = ResultPanel.centered(size: NSSize(width: 460, height: height), in: visible)
            XCTAssertEqual(placed.midX, visible.midX, accuracy: 0.01, "hauteur \(height)")
            XCTAssertEqual(placed.midY, visible.midY, accuracy: 0.01, "hauteur \(height)")
        }
    }

    func testLePanneauResteDansLEcran() {
        for height in [180.0, 300.0, 560.0, 900.0] {
            let placed = ResultPanel.centered(size: NSSize(width: 460, height: height), in: visible)
            XCTAssertTrue(visible.contains(placed), "cadre hors écran pour hauteur \(height)")
        }
    }

    /// Sur un second écran (origine décalée), le centre visé est bien celui de
    /// cet écran-là, pas de l'écran principal.
    func testCentreSurLEcranDonne() {
        let autre = NSRect(x: 1920, y: 0, width: 1440, height: 900)
        let placed = ResultPanel.centered(size: NSSize(width: 460, height: 200), in: autre)
        XCTAssertEqual(placed.midX, autre.midX, accuracy: 0.01)
        XCTAssertEqual(placed.midY, autre.midY, accuracy: 0.01)
    }
}

/// Pendant le streaming, le texte grandit d'un cran à la fois : la fenêtre suit
/// ces petits pas à l'instant, image par image, et glisse d'un easeOut sur les
/// seuls grands sauts (ouverture, bascule vers la palette ou une erreur). Sans
/// ce partage, un easeOut sur chaque cran rendrait la croissance saccadée.
final class PanelResizeAnimationTests: XCTestCase {
    func testUnPetitPasSuitLeTexteSansSAnimer() {
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 200, to: 200))
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 200, to: 224),
                       "une ligne de plus se suit à l'instant, pas en animation")
        XCTAssertFalse(ResultPanel.shouldAnimateResize(from: 300, to: 260))
    }

    func testUnGrandSautSAnime() {
        XCTAssertTrue(ResultPanel.shouldAnimateResize(from: 200, to: 460),
                      "l'ouverture d'un long résultat glisse au lieu de cogner")
        XCTAssertTrue(ResultPanel.shouldAnimateResize(from: 480, to: 210),
                      "le retour à une petite taille glisse aussi")
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
