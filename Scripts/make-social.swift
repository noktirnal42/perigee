// Renders docs/assets/social.png (1200x630). Usage: swift Scripts/make-social.swift <repo-root>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreText

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func load(_ p: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(root)/\(p)") as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}
let W = 1200, H = 630
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.02, green: 0.027, blue: 0.04, alpha: 1), CGColor(red: 0.2, green: 0.07, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [CGColor(red: 1, green: 0.42, blue: 0.24, alpha: 0.5), CGColor(red: 1, green: 0.42, blue: 0.24, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 1000, y: 40), startRadius: 0, endCenter: CGPoint(x: 1000, y: 40), endRadius: 600, options: [])
func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, color: CGColor, kern: CGFloat = 0) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color, kCTKernAttributeName: kern]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, ctx)
}
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
if let icon = load("docs/assets/icon-512.png") {
    ctx.saveGState(); ctx.addPath(CGPath(roundedRect: CGRect(x: 70, y: 440, width: 110, height: 110), cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()
    ctx.draw(icon, in: CGRect(x: 70, y: 440, width: 110, height: 110)); ctx.restoreGState()
}
text("PERIGEE", x: 200, y: 470, size: 64, bold: true, color: white, kern: 8)
text("Take command of your", x: 70, y: 330, size: 56, bold: true, color: white)
text("Starlink Wi-Fi.", x: 70, y: 262, size: 56, bold: true, color: CGColor(red: 1, green: 0.5, blue: 0.3, alpha: 1))
text("Tune channels & CAKE · A/B test stalls · see your satellite", x: 70, y: 190, size: 26, bold: false, color: CGColor(red: 0.85, green: 0.88, blue: 0.93, alpha: 1))
text("iOS + macOS  ·  open source  ·  unofficial", x: 70, y: 100, size: 20, bold: true, color: CGColor(red: 1, green: 0.55, blue: 0.35, alpha: 1), kern: 2)
if let shot = load("docs/assets/screens/ios-sky.png") {
    let w: CGFloat = 270, h = w * CGFloat(shot.height) / CGFloat(shot.width)
    ctx.saveGState(); ctx.translateBy(x: 900, y: -90); ctx.rotate(by: 0.07)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 38, cornerHeight: 38, transform: nil)); ctx.clip()
    ctx.draw(shot, in: CGRect(x: 0, y: 0, width: w, height: h)); ctx.restoreGState()
}
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(root)/docs/assets/social.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, nil); CGImageDestinationFinalize(out)
print("ok")
