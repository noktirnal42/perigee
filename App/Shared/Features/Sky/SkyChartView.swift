import SwiftUI
import StarlinkKit

/// Polar sky plot: zenith at the centre, horizon at the edge, north up. Shows every satellite above the horizon,
/// the dish's usable cone, where the dish is pointing, and the connected satellite's path.
struct SkyChartView: View {
    let snapshot: ConstellationSnapshot?
    let boresight: (az: Double, el: Double)?
    let trail: [(az: Double, el: Double, date: Date)]

    var body: some View {
        Canvas { ctx, size in
            let R = min(size.width, size.height) / 2 - 22
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ az: Double, _ el: Double) -> CGPoint {
                let r = R * (90 - el) / 90, a = az * .pi / 180
                return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
            }
            // dome
            let dome = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
            ctx.fill(dome, with: .radialGradient(Gradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.03, green: 0.04, blue: 0.07)]), center: c, startRadius: 0, endRadius: R))
            ctx.stroke(dome, with: .color(.white.opacity(0.35)), lineWidth: 1)
            for el in [30.0, 60.0] {
                let r = R * (90 - el) / 90
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.12)), lineWidth: 0.7)
            }
            // service cone: dish can only use satellites above this ring
            let rc = R * (90 - Constellation.minElevation) / 90
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rc, y: c.y - rc, width: 2 * rc, height: 2 * rc)), with: .color(Theme.ember.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            var cross = Path()
            cross.move(to: CGPoint(x: c.x, y: c.y - R)); cross.addLine(to: CGPoint(x: c.x, y: c.y + R))
            cross.move(to: CGPoint(x: c.x - R, y: c.y)); cross.addLine(to: CGPoint(x: c.x + R, y: c.y))
            ctx.stroke(cross, with: .color(.white.opacity(0.1)), lineWidth: 0.6)
            for (t, az) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                let a = az * .pi / 180
                ctx.draw(Text(t).font(.caption.weight(.bold)).foregroundStyle(t == "N" ? Theme.ember : .white.opacity(0.7)),
                         at: CGPoint(x: c.x + (R + 12) * CGFloat(sin(a)), y: c.y - (R + 12) * CGFloat(cos(a))))
            }
            guard let snap = snapshot else { return }

            // satellites above the horizon
            var low = Path(), usable = Path()
            for s in snap.satellites where s.elevation > 0 {
                let p = pt(s.azimuth, s.elevation)
                if s.elevation >= Constellation.minElevation { usable.addEllipse(in: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2)) }
                else { low.addEllipse(in: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)) }
            }
            ctx.fill(low, with: .color(.white.opacity(0.35)))
            ctx.fill(usable, with: .color(Theme.signal))

            // trail of the connected satellite
            if trail.count > 1 {
                var path = Path()
                for (i, p) in trail.enumerated() { let q = pt(p.az, p.el); i == 0 ? path.move(to: q) : path.addLine(to: q) }
                ctx.stroke(path, with: .color(Theme.ember.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 4]))
            }
            // dish boresight
            if let b = boresight, b.el > 0 {
                let p = pt(b.az, b.el)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(Theme.good), lineWidth: 1.6)
                var tick = Path()
                tick.move(to: CGPoint(x: p.x - 16, y: p.y)); tick.addLine(to: CGPoint(x: p.x - 7, y: p.y))
                tick.move(to: CGPoint(x: p.x + 7, y: p.y)); tick.addLine(to: CGPoint(x: p.x + 16, y: p.y))
                tick.move(to: CGPoint(x: p.x, y: p.y - 16)); tick.addLine(to: CGPoint(x: p.x, y: p.y - 7))
                tick.move(to: CGPoint(x: p.x, y: p.y + 7)); tick.addLine(to: CGPoint(x: p.x, y: p.y + 16))
                ctx.stroke(tick, with: .color(Theme.good), lineWidth: 1.6)
            }
            // connected satellite
            if let g = snap.connected?.satellite {
                let p = pt(g.azimuth, g.elevation)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)), with: .radialGradient(Gradient(colors: [Theme.ember.opacity(0.9), .clear]), center: p, startRadius: 0, endRadius: 18))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(.white))
                ctx.draw(Text(g.name).font(.caption2.weight(.bold)).foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y - 18))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(snapshot.map { "Sky chart: \($0.inView.count) satellites in your dish's field of view." } ?? "Sky chart")
    }
}
