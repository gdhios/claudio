// Dessine l'icône maître de Plume en PNG 1024×1024.
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

// Symbole wand.and.stars teinté blanc — le même que dans la barre de menus.
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
guard let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    FileHandle.standardError.write(Data("❌ Symbole wand.and.stars introuvable\n".utf8))
    exit(1)
}
let tinted = NSImage(size: symbol.size, flipped: false) { rect in
    symbol.draw(in: rect)
    NSColor.white.set()
    rect.fill(using: .sourceAtop)
    return true
}

let targetWidth = squircleRect.width * 0.62
let scale = targetWidth / tinted.size.width
let targetSize = NSSize(width: targetWidth, height: tinted.size.height * scale)
let symbolRect = NSRect(
    x: squircleRect.midX - targetSize.width / 2,
    y: squircleRect.midY - targetSize.height / 2,
    width: targetSize.width,
    height: targetSize.height
)

NSGraphicsContext.current?.saveGraphicsState()
let symbolShadow = NSShadow()
symbolShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
symbolShadow.shadowBlurRadius = 18
symbolShadow.shadowOffset = NSSize(width: 0, height: -8)
symbolShadow.set()
tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
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
