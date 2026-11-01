// Renders docs/assets/banner.png (README) and docs/assets/social.png (link previews) from the project art.
// Usage: swift Scripts/make-site-art.swift <repo-root>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func load(_ p: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(root)/\(p)") as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}
let cs = CGColorSpaceCreateDeviceRGB()
func canvas(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ ctx: CGContext, _ path: String) {
    let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(root)/\(path)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, ctx.makeImage()!, nil); CGImageDestinationFinalize(out)
}
func text(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, color: CGColor, kern: CGFloat = 0) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: kern]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, ctx)
}
/// Draws `img` filling `rect` (cover), anchored at `anchor` (0…1).
func fill(_ ctx: CGContext, _ img: CGImage, in rect: CGRect, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
    let s = max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height))
    let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
    ctx.saveGState(); ctx.clip(to: rect)
    ctx.draw(img, in: CGRect(x: rect.minX - (w - rect.width) * anchor.x, y: rect.minY - (h - rect.height) * anchor.y, width: w, height: h))
    ctx.restoreGState()
}
func gradient(_ ctx: CGContext, _ rect: CGRect, from: CGPoint, to: CGPoint, _ colors: [CGColor]) {
    ctx.saveGState(); ctx.clip(to: rect)
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!, start: from, end: to, options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    ctx.restoreGState()
}
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let ember = CGColor(red: 1, green: 0.54, blue: 0.36, alpha: 1)
let void = { (a: CGFloat) in CGColor(red: 0.02, green: 0.027, blue: 0.04, alpha: a) }

// MARK: README banner 1280x420
do {
    let W = 1280, H = 420, ctx = canvas(W, H), r = CGRect(x: 0, y: 0, width: W, height: H)
    ctx.setFillColor(void(1)); ctx.fill(r)
    if let orbit = load("docs/assets/mars-orbit.jpg") { fill(ctx, orbit, in: CGRect(x: 380, y: 0, width: 900, height: H), anchor: CGPoint(x: 0.5, y: 0.3)) }
    gradient(ctx, r, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 700, y: 0), [void(1), void(0.92), void(0)])
    if let icon = load("docs/assets/icon-512.png") {
        ctx.saveGState(); ctx.addPath(CGPath(roundedRect: CGRect(x: 64, y: 268, width: 84, height: 84), cornerWidth: 20, cornerHeight: 20, transform: nil)); ctx.clip()
        ctx.draw(icon, in: CGRect(x: 64, y: 268, width: 84, height: 84)); ctx.restoreGState()
    }
    text(ctx, "PERIGEE", x: 168, y: 282, size: 64, bold: true, color: white, kern: 12)
    text(ctx, "The control room your Starlink Wi-Fi never had.", x: 66, y: 210, size: 26, bold: false, color: CGColor(red: 0.95, green: 0.85, blue: 0.81, alpha: 1))
    text(ctx, "iOS  ·  macOS  ·  OPEN SOURCE  ·  UNOFFICIAL", x: 68, y: 150, size: 15, bold: true, color: ember, kern: 3)
    save(ctx, "docs/assets/banner.png")
}

// MARK: social card 1200x630
do {
    let W = 1200, H = 630, ctx = canvas(W, H), r = CGRect(x: 0, y: 0, width: W, height: H)
    ctx.setFillColor(void(1)); ctx.fill(r)
    if let hero = load("docs/assets/hero-mars.jpg") { fill(ctx, hero, in: r, anchor: CGPoint(x: 0.5, y: 0.2)) }
    gradient(ctx, r, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 820, y: 0), [void(0.96), void(0.82), void(0.15)])
    if let icon = load("docs/assets/icon-512.png") {
        ctx.saveGState(); ctx.addPath(CGPath(roundedRect: CGRect(x: 70, y: 440, width: 110, height: 110), cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()
        ctx.draw(icon, in: CGRect(x: 70, y: 440, width: 110, height: 110)); ctx.restoreGState()
    }
    text(ctx, "PERIGEE", x: 200, y: 470, size: 64, bold: true, color: white, kern: 8)
    text(ctx, "Take command of your", x: 70, y: 330, size: 56, bold: true, color: white)
    text(ctx, "Starlink Wi-Fi.", x: 70, y: 262, size: 56, bold: true, color: CGColor(red: 1, green: 0.5, blue: 0.3, alpha: 1))
    text(ctx, "Tune channels & CAKE · A/B test stalls · see your satellite", x: 70, y: 190, size: 26, bold: false, color: CGColor(red: 0.85, green: 0.88, blue: 0.93, alpha: 1))
    text(ctx, "iOS + macOS  ·  open source  ·  unofficial", x: 70, y: 100, size: 20, bold: true, color: ember, kern: 2)
    if let shot = load("docs/assets/screens/ios-sky.png") {
        let w: CGFloat = 270, h = w * CGFloat(shot.height) / CGFloat(shot.width)
        ctx.saveGState(); ctx.translateBy(x: 900, y: -90); ctx.rotate(by: 0.07)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 38, cornerHeight: 38, transform: nil)); ctx.clip()
        ctx.draw(shot, in: CGRect(x: 0, y: 0, width: w, height: h)); ctx.restoreGState()
    }
    save(ctx, "docs/assets/social.png")
}
print("ok")
