import XCTest
@testable import Claudio

/// Le réglage de taille touche à deux choses irréversibles : les clés écrites
/// dans UserDefaults, et l'aspect du panneau pour qui n'y touche jamais.
final class PanelTextSizeTests: XCTestCase {

    /// Les rawValue sont des clés de stockage : les renommer perdrait le
    /// réglage de tous ceux qui en ont choisi un.
    func testLesIdentifiantsStockesNeChangentPas() {
        XCTAssertEqual(PanelTextSize.allCases.map(\.rawValue),
                       ["small", "normal", "large", "extraLarge"])
    }

    /// Le réglage par défaut doit laisser le panneau exactement comme avant.
    func testLeReglageNormalNeChangeRien() {
        let normal = PanelTextSize.normal
        XCTAssertEqual(normal.scale, 1)
        XCTAssertEqual(normal.points(12.2), 12.2)
        XCTAssertEqual(normal.panelWidth, Constants.panelWidth)
        XCTAssertEqual(normal.maxTextHeight, Constants.panelMaxTextHeight)
    }

    /// Corps, largeur et hauteur croissent ensemble, du petit au très grand.
    func testToutGranditDansLeMemeSens() {
        let ordered = PanelTextSize.allCases
        for (petit, grand) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(petit.bodyPoints, grand.bodyPoints, "\(petit) → \(grand)")
            XCTAssertLessThanOrEqual(petit.panelWidth, grand.panelWidth, "\(petit) → \(grand)")
            XCTAssertLessThanOrEqual(petit.maxTextHeight, grand.maxTextHeight, "\(petit) → \(grand)")
        }
    }

    /// Un petit corps ne doit pas rétrécir le panneau : le texte y gagnerait
    /// des lignes plus longues sans que personne l'ait demandé.
    func testLePetitCorpsNeRetrecitPasLePanneau() {
        XCTAssertEqual(PanelTextSize.small.panelWidth, Constants.panelWidth)
        XCTAssertEqual(PanelTextSize.small.maxTextHeight, Constants.panelMaxTextHeight)
    }

    /// Le panneau reste un panneau : la zone de texte est plafonnée même au
    /// plus grand corps, sinon elle sortirait des petits écrans.
    func testLaZoneDeTexteResteBornee() {
        for size in PanelTextSize.allCases {
            XCTAssertLessThanOrEqual(size.maxTextHeight, 520, size.rawValue)
        }
    }

    /// Réglage absent ou écrit par une version qu'on ne connaît pas : on
    /// retombe sur le corps normal plutôt que sur un panneau vide.
    func testUnReglageInconnuRetombeSurNormal() {
        let key = "panelTextSize"
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(AppSettings.panelTextSize, .normal)

        defaults.set("gigantesque", forKey: key)
        XCTAssertEqual(AppSettings.panelTextSize, .normal)

        AppSettings.panelTextSize = .extraLarge
        XCTAssertEqual(AppSettings.panelTextSize, .extraLarge)
        XCTAssertEqual(defaults.string(forKey: key), "extraLarge")
    }
}
