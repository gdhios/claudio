// Dessine l'icône maître de Claudio en PNG 1024×1024 :
// petit robot original (PAS la mascotte d'Anthropic) avec une grosse moustache.
// Usage : swift Scripts/draw_icon.swift <sortie.png>
// (exécuté par Scripts/make_icon.sh, qui décline ensuite en .icns)

import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let canvas = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("❌ Impossible de créer le bitmap\n".utf8))
    exit(1)
}
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = ctx

let full = NSRect(x: 0, y: 0, width: canvas, height: canvas)

// Squircle façon macOS : ~10 % de marge, rayon ≈ 22,5 % de la largeur.
let inset = full.width * 0.098
let squircleRect = full.insetBy(dx: inset, dy: inset)
let radius = squircleRect.width * 0.225
let squircle = NSBezierPath(roundedRect: squircleRect, xRadius: radius, yRadius: radius)

// Ombre portée douce sous la tuile.
NSGraphicsContext.current?.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
tileShadow.shadowBlurRadius = 24
tileShadow.shadowOffset = NSSize(width: 0, height: -10)
tileShadow.set()
NSColor.black.setFill()  // couleur écrasée par le dégradé, sert au tracé de l'ombre
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Dégradé indigo → violet, du haut-gauche vers le bas-droit.
let indigo = NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.93, alpha: 1)
let violet = NSColor(calibratedRed: 0.63, green: 0.29, blue: 0.90, alpha: 1)
NSGradient(starting: indigo, ending: violet)?.draw(in: squircle, angle: -65)

// Reflet discret sur la moitié haute.
NSGradient(
    starting: NSColor.white.withAlphaComponent(0.20),
    ending: NSColor.white.withAlphaComponent(0)
)?.draw(in: squircle, angle: -90)

// Liseré intérieur pour détacher la tuile des fonds sombres.
let borderPath = NSBezierPath(
    roundedRect: squircleRect.insetBy(dx: 3, dy: 3),
    xRadius: radius - 3, yRadius: radius - 3
)
borderPath.lineWidth = 6
NSColor.white.withAlphaComponent(0.18).setStroke()
borderPath.stroke()

// ---- Robot moustachu ----
// Toutes les cotes sont relatives au côté S du squircle, origine squircleRect.
let S = squircleRect.width
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: squircleRect.minX + x * S, y: squircleRect.minY + y * S)
}
let cx: CGFloat = 0.5

let robotWhite = NSColor(calibratedWhite: 0.98, alpha: 1)
let eyeColor = NSColor(calibratedRed: 0.24, green: 0.17, blue: 0.55, alpha: 1)
let mustacheColor = NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.16, alpha: 1)

// Le robot entier projette une ombre douce sur la tuile.
NSGraphicsContext.current?.saveGraphicsState()
let robotShadow = NSShadow()
robotShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
robotShadow.shadowBlurRadius = 20
robotShadow.shadowOffset = NSSize(width: 0, height: -9)
robotShadow.set()

// Antenne : tige + boule au sommet.
let stemW = 0.026 * S
let stemRect = NSRect(x: pt(cx, 0).x - stemW / 2, y: pt(0, 0.665).y, width: stemW, height: 0.075 * S)
robotWhite.setFill()
NSBezierPath(roundedRect: stemRect, xRadius: stemW / 2, yRadius: stemW / 2).fill()
let bulbD = 0.075 * S
let bulbRect = NSRect(x: pt(cx, 0).x - bulbD / 2, y: pt(0, 0.735).y - bulbD / 2 + bulbD / 2, width: bulbD, height: bulbD)
NSBezierPath(ovalIn: bulbRect).fill()

// Oreilles latérales.
let earW = 0.055 * S, earH = 0.16 * S
for side: CGFloat in [-1, 1] {
    let earX = pt(cx, 0).x + side * (0.25 * S + earW / 2) - earW / 2
    let earRect = NSRect(x: earX, y: pt(0, 0.490).y - earH / 2, width: earW, height: earH)
    NSBezierPath(roundedRect: earRect, xRadius: earW / 2, yRadius: earW / 2).fill()
}

// Tête : rectangle arrondi.
let headW = 0.50 * S, headH = 0.38 * S
let headRect = NSRect(x: pt(cx, 0).x - headW / 2, y: pt(0, 0.490).y - headH / 2, width: headW, height: headH)
NSBezierPath(roundedRect: headRect, xRadius: 0.09 * S, yRadius: 0.09 * S).fill()

NSGraphicsContext.current?.restoreGraphicsState()

// Yeux ronds, au-dessus de la moustache.
eyeColor.setFill()
let eyeD = 0.085 * S
for side: CGFloat in [-1, 1] {
    let center = pt(cx + side * 0.105, 0.545)
    let eyeRect = NSRect(x: center.x - eyeD / 2, y: center.y - eyeD / 2, width: eyeD, height: eyeD)
    NSBezierPath(ovalIn: eyeRect).fill()
}
// Petit éclat blanc dans chaque œil.
NSColor.white.withAlphaComponent(0.85).setFill()
let glintD = 0.026 * S
for side: CGFloat in [-1, 1] {
    let center = pt(cx + side * 0.105 + 0.018, 0.562)
    let glintRect = NSRect(x: center.x - glintD / 2, y: center.y - glintD / 2, width: glintD, height: glintD)
    NSBezierPath(ovalIn: glintRect).fill()
}

// Grosse moustache en guidon : deux moitiés symétriques, pointes relevées.
// Elle chevauche le bas de la tête et déborde plus large que la tête.
func mustacheHalf(side: CGFloat) -> NSBezierPath {
    let oy: CGFloat = 0.390  // ligne médiane de la moustache
    func m(_ x: CGFloat, _ y: CGFloat) -> NSPoint { pt(cx + side * x, oy + y) }
    let path = NSBezierPath()
    // Bord supérieur : du creux central vers la pointe externe relevée.
    path.move(to: m(0, 0.045))
    path.curve(to: m(0.17, 0.050), controlPoint1: m(0.06, 0.075), controlPoint2: m(0.12, 0.072))
    path.curve(to: m(0.315, 0.130), controlPoint1: m(0.235, 0.030), controlPoint2: m(0.290, 0.055))
    // Pointe : petit retour serré vers l'intérieur.
    path.curve(to: m(0.258, 0.030), controlPoint1: m(0.325, 0.105), controlPoint2: m(0.300, 0.050))
    // Bord inférieur : retour vers le centre, plus bas (épaisseur).
    path.curve(to: m(0.10, -0.058), controlPoint1: m(0.215, -0.010), controlPoint2: m(0.16, -0.048))
    path.curve(to: m(0, -0.052), controlPoint1: m(0.055, -0.065), controlPoint2: m(0.02, -0.060))
    path.close()
    return path
}

NSGraphicsContext.current?.saveGraphicsState()
let mustacheShadow = NSShadow()
mustacheShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
mustacheShadow.shadowBlurRadius = 12
mustacheShadow.shadowOffset = NSSize(width: 0, height: -6)
mustacheShadow.set()
mustacheColor.setFill()
let mustache = NSBezierPath()
mustache.append(mustacheHalf(side: 1))
mustache.append(mustacheHalf(side: -1))
mustache.fill()
NSGraphicsContext.current?.restoreGraphicsState()

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("✅ \(outputPath)")
} catch {
    FileHandle.standardError.write(Data("❌ Écriture impossible : \(error)\n".utf8))
    exit(1)
}
