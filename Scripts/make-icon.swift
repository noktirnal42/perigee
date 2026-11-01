// Renders Perigee's app icon procedurally. Usage: swift Scripts/make-icon.swift <outDir>
// Concept: the lowest point of an orbit ("perigee") — a bright satellite grazing a faceted red-planet limb.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Variant { case standard, dark, tinted }

func hash(_ x: Int, _ y: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263)) ^ 0x9E3779B97F4A7C15
    h = (h ^ (h >> 13)) &* 1274126177; h ^= h >> 16
    return Double(h & 0xFFFF) / 65535
}

func render(size S: Int, variant: Variant, rounded: Bool) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(S) / 1024
    ctx.scaleBy(x: k, y: k)
    // Work in a top-left origin 1024 space.
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)

    func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    let gray = variant == .tinted
    func tone(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        if gray { let y = 0.3 * r + 0.59 * g + 0.11 * b; return col(y, y, y, a) }
        return col(r, g, b, a)
    }

    // Icon shape (macOS gets an inset rounded square; iOS is full-bleed and masked by the system)
    let inset: CGFloat = rounded ? 100 : 0
    let rect = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    if rounded {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: col(0, 0, 0, 0.45))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)); ctx.setFillColor(col(0.02, 0.03, 0.04)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)); ctx.clip()
    }
    let u = rect.width / 1024   // art scale within the rect
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }

    // Background
    let bgTop = variant == .dark ? 0.0 : 0.02
    let g = CGGradient(colorsSpace: cs, colors: [tone(bgTop + 0.01, bgTop + 0.015, 0.035), tone(0.10, 0.035, 0.05)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: P(512, 0), end: P(512, 1024), options: [])
    // Stars
    for i in 0..<70 {
        let x = hash(i, 11) * 1024, y = hash(i, 12) * 560, r = 1 + hash(i, 13) * 2.4
        ctx.setFillColor(tone(1, 1, 1, 0.25 + 0.6 * hash(i, 14)))
        ctx.fillEllipse(in: CGRect(x: P(x, y).x, y: P(x, y).y, width: r * u, height: r * u))
    }

    // Planet limb: faceted disc
    let c = P(512, 1330), R = 860 * u
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)); ctx.clip()
    let rings = 30, seg = 72
    var grid = [[CGPoint]]()
    for ri in 0...rings {
        var row = [CGPoint]()
        let r = R * CGFloat(ri) / CGFloat(rings)
        for si in 0...seg {
            let a = Double(si % seg) / Double(seg) * 2 * .pi
            let j = ri == rings ? 0 : (hash(ri, si % seg) - 0.5) * 22 * u
            row.append(CGPoint(x: c.x + (r + j) * CGFloat(cos(a)), y: c.y + (r + j) * CGFloat(sin(a))))
        }
        grid.append(row)
    }
    func shade(_ t: [CGPoint], _ seed: Int) {
        let mid = CGPoint(x: (t[0].x + t[1].x + t[2].x) / 3, y: (t[0].y + t[1].y + t[2].y) / 3)
        let nx = Double(mid.x - c.x) / Double(R), ny = Double(mid.y - c.y) / Double(R)
        let rad = hypot(nx, ny)
        let facet = hash(seed, 77)
        let rim = pow(max(0, rad - 0.55) / 0.45, 1.6)                 // lit by the horizon glow
        let sun = max(0, -(nx * -0.5 + ny * -0.85))                   // key light from upper-left
        let b = min(1, 0.06 + 0.78 * rim * (0.55 + 0.6 * facet) + 0.30 * sun * rim)
        ctx.setFillColor(tone(0.10 + 0.95 * b, 0.025 + 0.46 * b, 0.035 + 0.20 * b))
        ctx.move(to: t[0]); ctx.addLine(to: t[1]); ctx.addLine(to: t[2]); ctx.closePath(); ctx.fillPath()
        ctx.setStrokeColor(tone(0, 0, 0, 0.10)); ctx.setLineWidth(0.8); ctx.move(to: t[0]); ctx.addLine(to: t[1]); ctx.addLine(to: t[2]); ctx.closePath(); ctx.strokePath()
    }
    for ri in 0..<rings { for si in 0..<seg {
        let p00 = grid[ri + 1][si], p01 = grid[ri + 1][si + 1], p10 = grid[ri][si], p11 = grid[ri][si + 1]
        shade([p00, p01, p10], ri * 200 + si)
        shade([p01, p11, p10], ri * 200 + si + 9000)
    } }
    ctx.restoreGState()
    // Atmosphere glow on the limb
    for i in 0..<14 {
        let w = CGFloat(i) * 7 * u
        ctx.setStrokeColor(tone(1, 0.55, 0.28, 0.20 * (1 - Double(i) / 14)))
        ctx.setLineWidth(8 * u + w)
        ctx.strokeEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
    }
    ctx.setStrokeColor(tone(1, 0.82, 0.62, 0.95)); ctx.setLineWidth(3 * u)
    ctx.strokeEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))

    // Orbit ellipse (tilted), brightest near perigee (lower left)
    ctx.saveGState()
    ctx.translateBy(x: P(512, 360).x, y: P(512, 360).y); ctx.rotate(by: -0.16)
    let rx = 500 * u, ry = 210 * u
    let steps = 220
    for i in 0..<steps {
        let a0 = Double(i) / Double(steps) * 2 * .pi, a1 = Double(i + 1) / Double(steps) * 2 * .pi
        // perigee at angle ~ 100° (bottom-left in screen space since y is down)
        let near = 0.5 + 0.5 * cos(a0 - 1.75)
        ctx.setStrokeColor(tone(0.9, 0.96, 1, 0.22 + 0.78 * pow(near, 2.2)))
        ctx.setLineWidth((5 + 6 * pow(near, 3)) * u)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: rx * CGFloat(cos(a0)), y: ry * CGFloat(sin(a0))))
        ctx.addLine(to: CGPoint(x: rx * CGFloat(cos(a1)), y: ry * CGFloat(sin(a1)))); ctx.strokePath()
    }
    // Satellite at perigee, glowing
    let sa = 1.75
    let sp = CGPoint(x: rx * CGFloat(cos(sa)), y: ry * CGFloat(sin(sa)))
    let glow = CGGradient(colorsSpace: cs, colors: [tone(0.9, 0.97, 1, 0.95), tone(0.6, 0.85, 1, 0.35), tone(0.6, 0.85, 1, 0)] as CFArray, locations: [0, 0.25, 1])!
    ctx.drawRadialGradient(glow, startCenter: sp, startRadius: 0, endCenter: sp, endRadius: 120 * u, options: [])
    ctx.setFillColor(tone(1, 1, 1)); ctx.fillEllipse(in: CGRect(x: sp.x - 15 * u, y: sp.y - 15 * u, width: 30 * u, height: 30 * u))
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
write(render(size: 1024, variant: .standard, rounded: false), "\(out)/icon-ios.png")
write(render(size: 1024, variant: .dark, rounded: false), "\(out)/icon-ios-dark.png")
write(render(size: 1024, variant: .tinted, rounded: false), "\(out)/icon-ios-tinted.png")
write(render(size: 1024, variant: .standard, rounded: true), "\(out)/icon-mac-1024.png")
print("icons written to \(out)")
