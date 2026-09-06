import AppKit
import SwiftUI

/// Claudio's mascot, drawn natively.
///
/// The paths are those of `icon/claudio_mascotte.svg`, "bust" framing,
/// quoted without retouching: that file is the source of truth. The package
/// declares no resource, hence the drawing as `Path` rather than an asset.
///
/// Only the eyes change from one state to another: that's what holds the
/// character together.
struct ClaudioMascot: View {
    /// The four gazes of the master file. Four, not six: at the
    /// size of a menu bar, the eyeball is two and a half dots and
    /// only the *silhouette* of the eye reads. Shifting a pupil inside it
    /// doesn't say "he's looking elsewhere," it says "his eyes are
    /// crooked." So each state changes shape, not direction.
    enum Gaze: Equatable {
        /// Open eye, centered pupil. He's waiting, available.
        case repos
        /// Closed eyes. He's focusing while the answer comes in.
        case veille
        /// Smiling eyes. It's done.
        case fait
        /// Full eyeballs, no pupil. Blank gaze: he can't do anything.
        case vide
    }

    var gaze: Gaze = .repos
    /// Height of the drawing; the width follows the master file's framing.
    var height: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            Self.draw(gaze: gaze, in: &context, size: size)
        }
        .frame(width: MascotGrid.width(forHeight: height), height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - The gaze follows the phase

extension ClaudioMascot.Gaze {
    /// What Claudio is doing at this instant reads in his eyes.
    init(_ phase: CorrectionSession.Phase) {
        switch phase {
        case .capturing, .choosingAction, .askingInstruction: self = .repos
        case .streaming:                                      self = .veille
        case .done:                                           self = .fait
        case .noSelection, .missingKey, .error:               self = .vide
        }
    }
}

// MARK: - Grid and colors

/// The master file's grid: 512 to a side, framed on the bust.
private enum MascotGrid {
    static let frame = CGRect(x: 52, y: 52, width: 408, height: 310)

    /// The panel is permanently dark: this is the light version of the
    /// master file, the one meant for a dark background.
    static let trait = Color.white
    static let creux = Color(red: 49 / 255, green: 16 / 255, blue: 79 / 255)   // #31104f
    static let oeil = Color.white
    static let pupille = creux

    /// Head crop: beyond it lie the ring's "legs," which the
    /// mustache covers.
    static let coupeTete = CGRect(x: 120, y: 60, width: 272, height: 211)

    /// Scale factor from the grid to a render area.
    static func scale(into size: CGSize) -> CGFloat {
        min(size.width / frame.width, size.height / frame.height)
    }

    /// From the master file's grid to a render area, centered and
    /// with proportions kept.
    static func map(into size: CGSize) -> CGAffineTransform {
        let scale = scale(into: size)
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (size.width - frame.width * scale) / 2,
                y: (size.height - frame.height * scale) / 2))
    }

    /// Width called for by a given height.
    static func width(forHeight height: CGFloat) -> CGFloat {
        height * frame.width / frame.height
    }
}

// MARK: - Logo paths, quoted

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

// MARK: - Drawing

extension ClaudioMascot {
    /// Renders the bust then the gaze, scaled to the given area.
    fileprivate static func draw(gaze: Gaze, in context: inout GraphicsContext, size: CGSize) {
        let map = MascotGrid.map(into: size)
        func place(_ path: Path) -> Path { path.applying(map) }

        // ── Antenna: the shaft then the ball, geometry from the original logo.
        context.fill(place(Path(CGRect(x: 250.5, y: 114, width: 11, height: 23.613))),
                     with: .color(MascotGrid.trait))
        context.fill(place(Path(ellipseIn: CGRect(x: 256 - 21.255, y: 96.745 - 21.255,
                                                  width: 42.51, height: 42.51))),
                     with: .color(MascotGrid.trait))

        // ── Head: the ring and its hollow, cropped at mustache height.
        context.drawLayer { layer in
            layer.clip(to: place(Path(MascotGrid.coupeTete)))
            layer.fill(place(svgPath(MascotTrace.teteAnneau)),
                       with: .color(MascotGrid.trait), style: FillStyle(eoFill: true))
            layer.fill(place(svgPath(MascotTrace.teteInterieur)),
                       with: .color(MascotGrid.creux))
        }

        // ── Mustache: solid, it covers the bottom of the head by itself.
        context.fill(place(svgPath(MascotTrace.moustache)), with: .color(MascotGrid.trait))

        // ── Gaze.
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

    /// The arc `M199,194 A21,21 0 0 1 239,194` from the master file, and its
    /// mirror: a chord of 40 for a radius of 21, so a center placed
    /// just below the chord and an arc bowing upward.
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

    /// The scale applied by `place`, for strokes whose thickness is
    /// expressed in the master file's grid.
    private static func scaleOf(_ place: (Path) -> Path) -> CGFloat {
        let repere = place(Path(CGRect(x: 0, y: 0, width: 100, height: 100)))
        return repere.boundingRect.width / 100
    }
}

/// What a gaze adds to the head: inked shapes, pupils
/// hollowed out inside them, arcs drawn. The panel paints them in two tones; the
/// menu bar template hollows the pupils out via alpha. A single
/// description, two renderings.
private struct Regard {
    var pleins: [Path] = []
    var creuses: [Path] = []
    var arcs: [Path] = []

    static let epaisseurArc: CGFloat = 11

    init(_ gaze: ClaudioMascot.Gaze) {
        /// A disk centered on the master file's eye line.
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

// MARK: - Claudio in the menu bar

extension ClaudioMascot {
    /// Claudio as a template image. The system only reads the alpha and recolors
    /// the rest: the hollow of the head and the pupils are therefore holes,
    /// exactly the master file read in negative.
    static func menuBarImage(gaze: Gaze = .repos, height: CGFloat = 18) -> NSImage {
        let size = CGSize(width: MascotGrid.width(forHeight: height).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let map = MascotGrid.map(into: rect.size)
            func place(_ path: Path) -> CGPath { path.applying(map).cgPath }

            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            // ── Antenna: the shaft then the ball.
            context.addPath(place(Path(CGRect(x: 250.5, y: 114, width: 11, height: 23.613))))
            context.addPath(place(Path(ellipseIn: CGRect(x: 256 - 21.255, y: 96.745 - 21.255,
                                                         width: 42.51, height: 42.51))))
            context.fillPath()

            // ── Head: the ring alone, cropped at mustache height.
            context.saveGState()
            context.addPath(place(Path(MascotGrid.coupeTete)))
            context.clip()
            context.addPath(place(svgPath(MascotTrace.teteAnneau)))
            context.fillPath(using: .evenOdd)
            context.restoreGState()

            // ── Mustache.
            context.addPath(place(svgPath(MascotTrace.moustache)))
            context.fillPath()

            // ── Gaze: eyeballs and pupils as one, filled with
            // even-odd: the pupils hollow out on their own.
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

// MARK: - SVG path reader

/// Minimal reader for SVG "path data": `M`, `L`, `H`, `V`, `C`, `Z`, in
/// absolute as well as relative form. That's all the logo's paths use:
/// no arcs, no exponential notation, no chained decimals.
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
    /// A point, absolute or offset from the current point depending on the command's case.
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
            // Unhandled command: stop rather than draw something wrong.
            return path
        }
    }
    return path
}
