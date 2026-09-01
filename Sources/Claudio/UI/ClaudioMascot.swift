import AppKit
import SwiftUI

/// La mascotte de Claudio, dessinée nativement.
///
/// Les tracés sont ceux de `icon/claudio_mascotte.svg`, châssis « buste »,
/// cités sans retouche : c'est ce fichier-là qui fait foi. Le paquet ne
/// déclare aucune ressource, d'où le dessin en `Path` plutôt qu'un asset.
///
/// Seuls les yeux changent d'un état à l'autre — c'est ce qui tient le
/// personnage ensemble.
struct ClaudioMascot: View {
    /// Les quatre regards du fichier maître. Quatre et pas six : à la
    /// taille d'une barre de menus, le globe fait deux points et demi et
    /// seule la *silhouette* de l'œil se lit. Déplacer une pupille dedans
    /// ne dit pas « il regarde ailleurs », ça dit « ses yeux sont de
    /// travers ». Chaque état change donc de forme, pas de direction.
    enum Gaze: Equatable {
        /// Œil ouvert, pupille centrée. Il attend, il est disponible.
        case repos
        /// Yeux clos. Il se concentre pendant que la réponse arrive.
        case veille
        /// Yeux qui sourient. C'est fait.
        case fait
        /// Globes pleins, sans pupille. Regard vide : il ne peut rien faire.
        case vide
    }

    var gaze: Gaze = .repos
    /// Hauteur du dessin ; la largeur suit le cadrage du fichier maître.
    var height: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            Self.draw(gaze: gaze, in: &context, size: size)
        }
        .frame(width: MascotGrid.width(forHeight: height), height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Le regard suit la phase

extension ClaudioMascot.Gaze {
    /// Ce que fait Claudio à cet instant se lit dans ses yeux.
    init(_ phase: CorrectionSession.Phase) {
        switch phase {
        case .capturing, .choosingAction, .askingInstruction: self = .repos
        case .streaming:                                      self = .veille
        case .done:                                           self = .fait
        case .noSelection, .missingKey, .error:               self = .vide
        }
    }
}

// MARK: - Grille et couleurs

/// La grille du fichier maître : 512 de côté, cadrée sur le buste.
private enum MascotGrid {
    static let frame = CGRect(x: 52, y: 52, width: 408, height: 310)

    /// Le panneau est sombre en permanence : c'est la version claire du
    /// fichier maître, celle qui s'applique sur fond sombre.
    static let trait = Color.white
    static let creux = Color(red: 49 / 255, green: 16 / 255, blue: 79 / 255)   // #31104f
    static let oeil = Color.white
    static let pupille = creux

    /// Découpe de la tête : au-delà, ce sont les jambes de l'anneau, que la
    /// moustache recouvre.
    static let coupeTete = CGRect(x: 120, y: 60, width: 272, height: 211)

    /// Facteur d'échelle de la grille vers une zone de rendu.
    static func scale(into size: CGSize) -> CGFloat {
        min(size.width / frame.width, size.height / frame.height)
    }

    /// De la grille du fichier maître vers une zone de rendu, centrée et
    /// à proportions gardées.
    static func map(into size: CGSize) -> CGAffineTransform {
        let scale = scale(into: size)
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (size.width - frame.width * scale) / 2,
                y: (size.height - frame.height * scale) / 2))
    }

    /// Largeur qu'appelle une hauteur donnée.
    static func width(forHeight height: CGFloat) -> CGFloat {
        height * frame.width / frame.height
    }
}

// MARK: - Tracés cités du logo

private enum MascotTrace {
    static let teteAnneau = """
    M364.5,182.25l0,102.5c0,28.286 -22.964,51.25 -51.25,51.25l-114.5,0c-28.286,0 \
    -51.25,-22.964 -51.25,-51.25l0,-102.5c0,-28.286 22.964,-51.25 51.25,-51.25l114.5,0c28.286,0 \
    51.25,22.964 51.25,51.25Z M349,189.571l0,87.857c0,24.245 -19.684,43.929 -43.929,43.929l-98.143,0c-24.245,0 \
    -43.929,-19.684 -43.929,-43.929l0,-87.857c0,-24.245 19.684,-43.929 43.929,-43.929l98.143,0c24.245,0 \
    43.929,19.684 43.929,43.929Z
    """

    static let teteInterieur = """
    M349,189.571l0,87.857c0,24.245 -19.684,43.929 -43.929,43.929l-98.143,0c-24.245,0 \
    -43.929,-19.684 -43.929,-43.929l0,-87.857c0,-24.245 19.684,-43.929 43.929,-43.929l98.143,0c24.245,0 \
    43.929,19.684 43.929,43.929Z
    """

    static let moustache = """
    M256,239.765c-26.2,-26.2 -72.05,-22.925 -98.25,6.55c-22.925,26.2 -55.675,32.75 -85.15,16.375c13.1,58.95 \
    62.225,91.7 114.625,75.325c29.475,-9.825 52.4,-32.75 68.775,-58.95c16.375,26.2 39.3,49.125 68.775,58.95c52.4,16.375 \
    101.525,-16.375 114.625,-75.325c-29.475,16.375 -62.225,9.825 -85.15,-16.375c-26.2,-29.475 -72.05,-32.75 -98.25,-6.55Z
    """
}

// MARK: - Dessin

extension ClaudioMascot {
    /// Rend le buste puis le regard, à l'échelle de la zone donnée.
    fileprivate static func draw(gaze: Gaze, in context: inout GraphicsContext, size: CGSize) {
        let map = MascotGrid.map(into: size)
        func place(_ path: Path) -> Path { path.applying(map) }

        // ── Antenne : la tige puis la boule, géométrie du logo d'origine.
        context.fill(place(Path(CGRect(x: 250.5, y: 114, width: 11, height: 23.613))),
                     with: .color(MascotGrid.trait))
        context.fill(place(Path(ellipseIn: CGRect(x: 256 - 21.255, y: 96.745 - 21.255,
                                                  width: 42.51, height: 42.51))),
                     with: .color(MascotGrid.trait))

        // ── Tête : l'anneau et son creux, coupés à hauteur de moustache.
        context.drawLayer { layer in
            layer.clip(to: place(Path(MascotGrid.coupeTete)))
            layer.fill(place(svgPath(MascotTrace.teteAnneau)),
                       with: .color(MascotGrid.trait), style: FillStyle(eoFill: true))
            layer.fill(place(svgPath(MascotTrace.teteInterieur)),
                       with: .color(MascotGrid.creux))
        }

        // ── Moustache : pleine, elle couvre d'elle-même le bas de la tête.
        context.fill(place(svgPath(MascotTrace.moustache)), with: .color(MascotGrid.trait))

        // ── Regard.
        drawGaze(gaze, in: &context, place: place)
    }

    private static func drawGaze(_ gaze: Gaze,
                                 in context: inout GraphicsContext,
                                 place: (Path) -> Path) {
        let regard = Regard(gaze)
        for forme in regard.pleins {
            context.fill(place(forme), with: .color(MascotGrid.oeil))
        }
        for forme in regard.creuses {
            context.fill(place(forme), with: .color(MascotGrid.pupille))
        }
        for forme in regard.arcs {
            context.stroke(place(forme), with: .color(MascotGrid.trait),
                           style: StrokeStyle(lineWidth: Regard.epaisseurArc * scaleOf(place),
                                              lineCap: .round))
        }
    }

    /// L'arc `M199,194 A21,21 0 0 1 239,194` du fichier maître, et son
    /// symétrique : une corde de 40 pour un rayon de 21, donc un centre posé
    /// juste sous la corde et un arc qui bombe vers le haut.
    fileprivate static func smile(centeredOn x: CGFloat) -> Path {
        let r: CGFloat = 21, demiCorde: CGFloat = 20, y: CGFloat = 194
        let creuse = (r * r - demiCorde * demiCorde).squareRoot()
        let centre = CGPoint(x: x, y: y + creuse)
        let ouverture = Angle(radians: atan2(-creuse, demiCorde))
        var path = Path()
        path.addArc(center: centre, radius: r,
                    startAngle: .degrees(180) - ouverture,
                    endAngle: ouverture,
                    clockwise: false)
        return path
    }

    /// L'échelle appliquée par `place`, pour les traits dont l'épaisseur est
    /// exprimée dans la grille du fichier maître.
    private static func scaleOf(_ place: (Path) -> Path) -> CGFloat {
        let repere = place(Path(CGRect(x: 0, y: 0, width: 100, height: 100)))
        return repere.boundingRect.width / 100
    }
}

/// Ce qu'un regard ajoute à la tête : des formes encrées, des pupilles
/// creusées dedans, des arcs tracés. Le panneau les peint en deux tons ; le
/// gabarit de la barre de menus creuse les pupilles à l'alpha. Une seule
/// description, deux rendus.
private struct Regard {
    var pleins: [Path] = []
    var creuses: [Path] = []
    var arcs: [Path] = []

    static let epaisseurArc: CGFloat = 11

    init(_ gaze: ClaudioMascot.Gaze) {
        /// Un disque centré sur la ligne des yeux du fichier maître.
        func disque(_ x: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: 187.481 - r, width: r * 2, height: r * 2))
        }
        switch gaze {
        case .repos:
            pleins = [disque(219, 23.5), disque(293, 23.5)]
            creuses = [disque(219, 12.5), disque(293, 12.5)]
        case .vide:
            pleins = [disque(219, 23.5), disque(293, 23.5)]
        case .veille:
            pleins = ([198, 272] as [CGFloat]).map {
                Path(roundedRect: CGRect(x: $0, y: 182, width: 42, height: 11),
                     cornerRadius: 5.5)
            }
        case .fait:
            arcs = [ClaudioMascot.smile(centeredOn: 219), ClaudioMascot.smile(centeredOn: 293)]
        }
    }
}

// MARK: - Claudio dans la barre de menus

extension ClaudioMascot {
    /// Claudio en image gabarit. Le système ne lit que l'alpha et recolore
    /// le reste : le creux de la tête et les pupilles sont donc des trous,
    /// exactement la lecture en négatif du fichier maître.
    static func menuBarImage(gaze: Gaze = .repos, height: CGFloat = 18) -> NSImage {
        let size = CGSize(width: MascotGrid.width(forHeight: height).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let map = MascotGrid.map(into: rect.size)
            func place(_ path: Path) -> CGPath { path.applying(map).cgPath }

            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            // ── Antenne : la tige puis la boule.
            context.addPath(place(Path(CGRect(x: 250.5, y: 114, width: 11, height: 23.613))))
            context.addPath(place(Path(ellipseIn: CGRect(x: 256 - 21.255, y: 96.745 - 21.255,
                                                         width: 42.51, height: 42.51))))
            context.fillPath()

            // ── Tête : l'anneau seul, coupé à hauteur de moustache.
            context.saveGState()
            context.addPath(place(Path(MascotGrid.coupeTete)))
            context.clip()
            context.addPath(place(svgPath(MascotTrace.teteAnneau)))
            context.fillPath(using: .evenOdd)
            context.restoreGState()

            // ── Moustache.
            context.addPath(place(svgPath(MascotTrace.moustache)))
            context.fillPath()

            // ── Regard : globes et pupilles d'un seul tenant, remplis en
            // pair-impair — les pupilles se creusent d'elles-mêmes.
            let regard = Regard(gaze)
            var oeil = Path()
            for forme in regard.pleins + regard.creuses { oeil.addPath(forme) }
            if !oeil.isEmpty {
                context.addPath(place(oeil))
                context.fillPath(using: .evenOdd)
            }
            for forme in regard.arcs { context.addPath(place(forme)) }
            if !regard.arcs.isEmpty {
                context.setLineWidth(Regard.epaisseurArc * MascotGrid.scale(into: rect.size))
                context.setLineCap(.round)
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Lecteur de tracé SVG

/// Lecteur minimal de « path data » SVG : `M`, `L`, `H`, `V`, `C`, `Z`, en
/// absolu comme en relatif. C'est tout ce qu'emploient les tracés du logo —
/// ni arcs, ni notation exponentielle, ni décimales enchaînées.
private func svgPath(_ data: String) -> Path {
    var path = Path()
    var point = CGPoint.zero
    var origin = CGPoint.zero
    var command: Character = "M"
    let chars = Array(data)
    var i = 0

    func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n"
            || chars[i] == "\t" || chars[i] == "\r" {
            i += 1
        }
    }
    func number() -> CGFloat {
        skipSeparators()
        var text = ""
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { text.append(chars[i]); i += 1 }
        while i < chars.count, chars[i].isNumber || chars[i] == "." { text.append(chars[i]); i += 1 }
        return CGFloat(Double(text) ?? 0)
    }
    /// Un point, absolu ou décalé du point courant selon la casse de la commande.
    func coordinate(relative: Bool) -> CGPoint {
        let x = number(), y = number()
        return relative ? CGPoint(x: point.x + x, y: point.y + y) : CGPoint(x: x, y: y)
    }

    while i < chars.count {
        skipSeparators()
        guard i < chars.count else { break }
        if chars[i].isLetter {
            command = chars[i]
            i += 1
        }
        let relative = command.isLowercase
        switch command {
        case "M", "m":
            point = coordinate(relative: relative)
            path.move(to: point)
            origin = point
            command = relative ? "l" : "L"
        case "L", "l":
            point = coordinate(relative: relative)
            path.addLine(to: point)
        case "H", "h":
            let x = number()
            point = CGPoint(x: relative ? point.x + x : x, y: point.y)
            path.addLine(to: point)
        case "V", "v":
            let y = number()
            point = CGPoint(x: point.x, y: relative ? point.y + y : y)
            path.addLine(to: point)
        case "C", "c":
            let c1 = coordinate(relative: relative)
            let c2 = coordinate(relative: relative)
            let end = coordinate(relative: relative)
            path.addCurve(to: end, control1: c1, control2: c2)
            point = end
        case "Z", "z":
            path.closeSubpath()
            point = origin
        default:
            // Commande non gérée : on s'arrête plutôt que de dessiner faux.
            return path
        }
    }
    return path
}
