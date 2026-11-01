import SwiftUI

/// Procedural low-poly Martian landscape: flat-shaded triangles over a drifting heightfield under a dusty sky.
/// Everything is drawn from a seed — there are no bitmap assets.
struct MarsTerrain: View {
    var seed: UInt64 = 7
    var animated = true
    var calm: Bool = false     // dims & flattens for use behind dense content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated || reduceMotion)) { tl in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, t: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: noise

    private static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263)) ^ (seed &* 0x9E3779B97F4A7C15)
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65535.0
    }
    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func noise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = smooth(x - floor(x)), yf = smooth(y - floor(y))
        let a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed), c = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed)
        return (a + (b - a) * xf) + ((c + (d - c) * xf) - (a + (b - a) * xf)) * yf
    }
    private func height(_ x: Double, _ z: Double) -> Double {
        let s = seed
        var h = Self.noise(x * 0.35, z * 0.35, s) * 1.0
        h += Self.noise(x * 0.8 + 11, z * 0.8 + 3, s &+ 1) * 0.42
        h += Self.noise(x * 1.9 + 5, z * 1.9 + 9, s &+ 2) * 0.14
        // Broad crater bowl in the foreground centre keeps the middle low for the hero objects.
        let bowl = exp(-pow((x - 5.0) / 3.2, 2)) * 0.55
        return (h - bowl) * (calm ? 0.5 : 1)
    }

    // MARK: drawing

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double) {
        // Sky
        let horizon = size.height * 0.34
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: Color(red: 0.03, green: 0.02, blue: 0.05), location: 0),
                    .init(color: Color(red: 0.20, green: 0.07, blue: 0.07), location: 0.5),
                    .init(color: Color(red: 0.74, green: 0.30, blue: 0.16), location: 1)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon + 6)))
        // Stars
        for i in 0..<46 {
            let x = Self.hash(i, 1, 99) * size.width, y = Self.hash(i, 2, 99) * horizon * 0.8
            let tw = 0.5 + 0.5 * sin(t * (0.6 + Self.hash(i, 3, 99)) + Double(i))
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.2 + 0.5 * tw * (1 - y / horizon))))
        }
        // Distant sun
        let sun = CGPoint(x: size.width * 0.78, y: horizon - 6)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 90, y: sun.y - 90, width: 180, height: 180)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.38).opacity(0.55), .clear]),
                                       center: sun, startRadius: 0, endRadius: 90))

        // Terrain mesh: rows march from the horizon toward the viewer.
        let cols = 22, rows = 15
        let drift = t * 0.08
        var verts = [[CGPoint]](), hs = [[Double]]()
        for r in 0...rows {
            let d = Double(r) / Double(rows)                       // 0 far → 1 near
            let persp = pow(d, 1.9)
            let y0 = horizon + (size.height - horizon) * persp
            let spread = 0.55 + 2.6 * persp                         // horizontal fan-out
            var rowV = [CGPoint](), rowH = [Double]()
            for c in 0...cols {
                let u = Double(c) / Double(cols) - 0.5
                let wx = Double(c) * 0.5 + 0.0, wz = Double(rows - r) * 0.5 + drift
                let h = height(wx, wz)
                rowH.append(h)
                let x = size.width * (0.5 + u * spread)
                let lift = h * (8 + 70 * persp)
                rowV.append(CGPoint(x: x, y: y0 - lift))
            }
            verts.append(rowV); hs.append(rowH)
        }
        let light = SIMD3<Double>(-0.5, 0.8, 0.35)
        for r in 0..<rows {
            for c in 0..<cols {
                let p00 = verts[r][c], p10 = verts[r][c + 1], p01 = verts[r + 1][c], p11 = verts[r + 1][c + 1]
                let h00 = hs[r][c], h10 = hs[r][c + 1], h01 = hs[r + 1][c], h11 = hs[r + 1][c + 1]
                for (tri, hh) in [([p00, p10, p01], [h00, h10, h01]), ([p10, p11, p01], [h10, h11, h01])] {
                    let dx = hh[1] - hh[0], dz = hh[2] - hh[0]
                    var n = SIMD3<Double>(-dx * 2.2, 1, -dz * 2.2)
                    n /= max(0.0001, (n * n).sum().squareRoot())
                    let lam = max(0.0, (n * light).sum() / (light * light).sum().squareRoot())
                    let depth = Double(r) / Double(rows)
                    let avgH = (hh[0] + hh[1] + hh[2]) / 3
                    // red-orange palette, lighter on lit faces, hazier with distance
                    let base = Color(red: 0.55 + 0.38 * lam + 0.12 * avgH, green: 0.17 + 0.22 * lam, blue: 0.10 + 0.08 * lam)
                    var path = Path()
                    path.move(to: tri[0]); path.addLine(to: tri[1]); path.addLine(to: tri[2]); path.closeSubpath()
                    ctx.fill(path, with: .color(base.opacity(0.35 + 0.65 * depth * 0.9 + 0.1)))
                    ctx.stroke(path, with: .color(.black.opacity(0.06)), lineWidth: 0.5)
                }
            }
        }
        // Atmospheric haze at the horizon and a vignette to seat the foreground in black.
        ctx.fill(Path(CGRect(x: 0, y: horizon - 10, width: size.width, height: 60)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.9, green: 0.45, blue: 0.25).opacity(0.35), .clear]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: horizon + 60)))
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [.clear, Theme.void.opacity(calm ? 0.95 : 0.85)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.55), endPoint: CGPoint(x: 0, y: size.height)))
    }
}
