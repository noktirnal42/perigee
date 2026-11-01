import SwiftUI
import StarlinkKit

enum HeroState { case online, degraded, offline, connecting
    var beam: Color { switch self { case .online: Theme.signal; case .degraded: Theme.warn; case .offline: Theme.bad.opacity(0.7); case .connecting: Theme.signal.opacity(0.5) } }
    var dot: Color { switch self { case .online: Theme.good; case .degraded: Theme.warn; case .offline: Theme.bad; case .connecting: Theme.info } }
    var label: String { switch self { case .online: "Online"; case .degraded: "Degraded"; case .offline: "Offline"; case .connecting: "Connecting" } }
}

/// The hero: a Mars horizon, the dish and router renders, thin glowing beams with travelling pulses, and a status chip.
struct HeroScene: View {
    var state: HeroState
    var dishTilt: Double = 24
    var statusText: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Both renders keep their natural aspect ratio; they're laid out by height so they never distort.
            let dishH = min(h * 0.46, w * 0.40), dishW = dishH * (1000.0 / 860.0)
            let routerH = min(h * 0.40, w * 0.30), routerW = routerH * (565.0 / 900.0)
            let dishRect = CGRect(x: w * 0.04, y: h * 0.36, width: dishW, height: dishH)
            let routerRect = CGRect(x: w * 0.68, y: h * 0.44, width: routerW, height: routerH)
            let dishAnchor = CGPoint(x: dishRect.midX + dishRect.width * 0.12, y: dishRect.minY + dishRect.height * 0.22)
            let routerAnchor = CGPoint(x: routerRect.midX, y: routerRect.minY + routerRect.height * 0.08)
            let satellite = CGPoint(x: w * 0.68, y: h * 0.14)

            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || state == .offline)) { tl in
                    let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    Image("HeroMars").resizable().scaledToFill()
                        .scaleEffect(1.08).offset(x: CGFloat(sin(t * 0.08)) * 10, y: 0)
                        .frame(width: w, height: h).clipped()
                }
                LinearGradient(colors: [.black.opacity(0.35), .clear, Theme.void.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                Image("DishRender").resizable().scaledToFit()
                    .frame(width: dishRect.width, height: dishRect.height)
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 14)
                    .position(x: dishRect.midX, y: dishRect.midY)
                Image("RouterRender").resizable().scaledToFit()
                    .frame(width: routerRect.width, height: routerRect.height)
                    .shadow(color: .black.opacity(0.55), radius: 16, y: 12)
                    .position(x: routerRect.midX, y: routerRect.midY)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                    Canvas { ctx, size in
                        let t = reduceMotion ? 0.35 : tl.date.timeIntervalSinceReferenceDate
                        beam(&ctx, from: satellite, to: dishAnchor, bend: -0.12, t: t, speed: 0.22, dashed: true)
                        beam(&ctx, from: dishAnchor, to: routerAnchor, bend: -0.22, t: t, speed: 0.35, dashed: state == .offline)
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
