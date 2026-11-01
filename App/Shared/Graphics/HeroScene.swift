import SwiftUI
import StarlinkKit

enum HeroState { case online, degraded, offline, connecting
    var beam: Color { switch self { case .online: Theme.signal; case .degraded: Theme.warn; case .offline: Theme.bad.opacity(0.7); case .connecting: Theme.signal.opacity(0.5) } }
    var dot: Color { switch self { case .online: Theme.good; case .degraded: Theme.warn; case .offline: Theme.bad; case .connecting: Theme.info } }
    var label: String { switch self { case .online: "Online"; case .degraded: "Degraded"; case .offline: "Offline"; case .connecting: "Connecting" } }
}

/// The hero: Mars terrain, dish, router and thin glowing beams with travelling pulses, plus a status chip.
struct HeroScene: View {
    var state: HeroState
    var dishTilt: Double = 24
    var statusText: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dishRect = CGRect(x: w * 0.07, y: h * 0.34, width: min(w * 0.36, h * 0.5), height: min(w * 0.36, h * 0.5))
            let routerRect = CGRect(x: w * 0.58, y: h * 0.50, width: min(w * 0.28, h * 0.36), height: min(w * 0.28, h * 0.36))
            let dishAnchor = CGPoint(x: dishRect.midX + dishRect.width * 0.12, y: dishRect.minY + dishRect.height * 0.40)
            let routerAnchor = CGPoint(x: routerRect.midX, y: routerRect.minY + routerRect.height * 0.30)
            let satellite = CGPoint(x: w * 0.66, y: h * 0.14)

            ZStack {
                MarsTerrain(animated: state != .offline)
                DishRender(tilt: dishTilt, glow: state.dot)
                    .frame(width: dishRect.width, height: dishRect.height).position(x: dishRect.midX, y: dishRect.midY)
                RouterRender(led: state.dot)
                    .frame(width: routerRect.width, height: routerRect.height).position(x: routerRect.midX, y: routerRect.midY)

                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                    Canvas { ctx, size in
                        let t = reduceMotion ? 0.35 : tl.date.timeIntervalSinceReferenceDate
                        beam(&ctx, from: satellite, to: dishAnchor, bend: -0.12, t: t, speed: 0.22, dashed: true)
                        beam(&ctx, from: dishAnchor, to: routerAnchor, bend: -0.22, t: t, speed: 0.35, dashed: state == .offline)
                        // satellite glint
                        ctx.fill(Path(ellipseIn: CGRect(x: satellite.x - 3, y: satellite.y - 3, width: 6, height: 6)), with: .color(.white))
                        ctx.fill(Path(ellipseIn: CGRect(x: satellite.x - 14, y: satellite.y - 14, width: 28, height: 28)),
                                 with: .radialGradient(Gradient(colors: [state.beam.opacity(0.5), .clear]), center: satellite, startRadius: 0, endRadius: 14))
                    }
                }
                .allowsHitTesting(false)

                VStack { Spacer(); StatusChip(text: statusText ?? state.label, color: state.dot, pulse: state == .online).padding(.bottom, 14) }
            }
            .frame(width: w, height: h)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dish and router illustration. Status: \(statusText ?? state.label)")
    }

    private func beam(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, bend: CGFloat, t: Double, speed: Double, dashed: Bool) {
        let mid = CGPoint(x: (a.x + b.x) / 2 + (b.y - a.y) * bend, y: (a.y + b.y) / 2 - abs(b.x - a.x) * 0.08)
        var p = Path(); p.move(to: a); p.addQuadCurve(to: b, control: mid)
        let style = StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: dashed ? [3, 5] : [])
        ctx.stroke(p, with: .color(state.beam.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: dashed ? [3, 5] : []))
        ctx.stroke(p, with: .color(state.beam.opacity(0.18)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        ctx.stroke(p, with: .color(.white), style: style)
        // travelling pulses
        guard state != .offline else { return }
        for i in 0..<3 {
            let f = (t * speed + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let q = quad(a, mid, b, f)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)),
                     with: .radialGradient(Gradient(colors: [state.beam.opacity(0.75), .clear]), center: q, startRadius: 0, endRadius: 9))
        }
    }

    private func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
}
