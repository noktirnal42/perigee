import SwiftUI
import StarlinkKit

/// Interactive orthographic globe: coastlines, every satellite, the ones in view, and the one the dish is (probably) using.
struct GlobeView: View {
    let snapshot: ConstellationSnapshot?
    let observer: Observer?
    @State private var lon0: Double = -100
    @State private var lat0: Double = 25
    @State private var dragStart: (Double, Double)?
    @State private var follow = true
    @State private var zoom: Double = 1
    @State private var zoomStart: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let coast = WorldGeometry.coastlines

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
                Canvas { ctx, size in draw(&ctx, size, t: tl.date.timeIntervalSinceReferenceDate) }
            }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    follow = false
                    let s = dragStart ?? (lon0, lat0); dragStart = s
                    lon0 = s.0 - Double(g.translation.width) * 0.35
                    lat0 = max(-85, min(85, s.1 + Double(g.translation.height) * 0.35))
                }
                .onEnded { _ in dragStart = nil })
            .simultaneousGesture(MagnifyGesture().onChanged { g in let z = zoomStart ?? zoom; zoomStart = z; zoom = max(0.8, min(4, z * g.magnification)) }.onEnded { _ in zoomStart = nil })
            Button { follow = true; zoom = 1.9; recenter() } label: { Label("Center on me", systemImage: "location.fill").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).card(radius: 18) }
                .buttonStyle(.plain).padding(10).opacity(observer == nil ? 0 : 1)
        }
        .onAppear { recenter() }
        .onChange(of: observer) { _, _ in if follow { recenter() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.map { "Globe showing \($0.satellites.count) satellites, \($0.inView.count) in view of your dish." } ?? "Globe")
    }

    private func recenter() {
        guard let o = observer else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { lon0 = o.longitude; lat0 = max(-60, min(60, o.latitude - 8)) }
    }

    // MARK: projection

    private struct Cam { let lon: Double, lat: Double
        var cl: Double { cos(lon * .pi / 180) }
        var sl: Double { sin(lon * .pi / 180) }
        var cp: Double { cos(lat * .pi / 180) }
        var sp: Double { sin(lat * .pi / 180) }
        /// Returns (screen x, screen y, depth) for an ECEF-direction vector.
        func project(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            let x1 = x * cl + y * sl, y1 = -x * sl + y * cl
            let x2 = x1 * cp + z * sp, z2 = -x1 * sp + z * cp
            return (y1, z2, x2)
        }
    }

    private func unit(_ lat: Double, _ lon: Double, r: Double = 1) -> (Double, Double, Double) {
        let la = lat * .pi / 180, lo = lon * .pi / 180
        return (r * cos(la) * cos(lo), r * cos(la) * sin(lo), r * sin(la))
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double) {
        let cam = Cam(lon: lon0, lat: lat0)
        let R = min(size.width, size.height) * 0.40 * CGFloat(zoom)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        func pt(_ v: (Double, Double, Double)) -> CGPoint { CGPoint(x: c.x + CGFloat(v.0) * R, y: c.y - CGFloat(v.1) * R) }

        // Atmosphere + body
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 1.12, y: c.y - R * 1.12, width: R * 2.24, height: R * 2.24)),
                 with: .radialGradient(Gradient(colors: [Theme.ember.opacity(0.35), Theme.ember.opacity(0.0)]), center: c, startRadius: R * 0.98, endRadius: R * 1.12))
        let body = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        ctx.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 0.13, green: 0.10, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.05)]),
                                             center: CGPoint(x: c.x - R * 0.35, y: c.y - R * 0.4), startRadius: 0, endRadius: R * 1.4))
        ctx.stroke(body, with: .color(Theme.dust.opacity(0.55)), lineWidth: 1)

        // Graticule
        var grat = Path()
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) { addLine(&grat, (0...72).map { (lat, Double($0) * 5 - 180) }, cam, pt) }
        for lon in stride(from: -180.0, to: 180.0, by: 30.0) { addLine(&grat, (0...36).map { (Double($0) * 5 - 90, lon) }, cam, pt) }
        ctx.stroke(grat, with: .color(.white.opacity(0.07)), lineWidth: 0.6)

        // Coastlines
        var coast = Path()
        for line in Self.coast { addLine(&coast, line.map { (Double($0.y), Double($0.x)) }, cam, pt) }
        ctx.stroke(coast, with: .color(Theme.dust.opacity(0.55)), lineWidth: 0.8)

        guard let snap = snapshot else { return }
        func satVec(_ s: SatelliteState) -> (Double, Double, Double) {
            // Lift altitude visually (×~2.5) so the shell reads as floating above the globe.
            unit(s.latitude, s.longitude, r: 1 + s.altitudeKm / 6371 * 2.5)
        }

        // Everything in the constellation: a single batched path of tiny dots.
        var dots = Path()
        let inViewIDs = Set(snap.inView.map(\.id))
        for s in snap.satellites where !inViewIDs.contains(s.id) {
            let v = cam.project(satVec(s).0, satVec(s).1, satVec(s).2)
            if v.2 < 0 && (v.0 * v.0 + v.1 * v.1) < 1 { continue }   // hidden behind the globe
            let p = pt(v)
            dots.addRect(CGRect(x: p.x - 0.7, y: p.y - 0.7, width: 1.4, height: 1.4))
        }
        ctx.fill(dots, with: .color(Theme.signal.opacity(0.55)))

        // Footprint of the connected satellite
        if let g = snap.connected?.satellite {
            let re = 6371.0, h = g.altitudeKm
            let el = Constellation.minElevation * .pi / 180
            let lam = acos(re * cos(el) / (re + h)) - el                 // central angle to the coverage edge
            var ring = Path()
            let la = g.latitude * .pi / 180, lo = g.longitude * .pi / 180
            var started = false
            for i in 0...90 {
                let b = Double(i) / 90 * 2 * .pi
                let lat2 = asin(sin(la) * cos(lam) + cos(la) * sin(lam) * cos(b))
                let lon2 = lo + atan2(sin(b) * sin(lam) * cos(la), cos(lam) - sin(la) * sin(lat2))
                let v = cam.project(cos(lat2) * cos(lon2), cos(lat2) * sin(lon2), sin(lat2))
                if v.2 > 0 { let p = pt(v); started ? ring.addLine(to: p) : ring.move(to: p); started = true } else { started = false }
            }
            ctx.stroke(ring, with: .color(Theme.ember.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        }

        // Satellites in view of the dish
        for s in snap.inView {
            let sv = satVec(s)
            let v = cam.project(sv.0, sv.1, sv.2)
            if v.2 < 0 && (v.0 * v.0 + v.1 * v.1) < 1 { continue }
            let p = pt(v)
            let isConn = snap.connected?.satellite.id == s.id
            if !isConn { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)), with: .color(.white)) }
        }

        // Observer + beam to the connected satellite
        if let o = observer {
            let ov = cam.project(unit(o.latitude, o.longitude).0, unit(o.latitude, o.longitude).1, unit(o.latitude, o.longitude).2)
            let op = pt(ov)
            if let g = snap.connected?.satellite {
                let sv = satVec(g)
                let spv = cam.project(sv.0, sv.1, sv.2)
                let sp = pt(spv)
                if ov.2 > 0 {
                    var beam = Path(); beam.move(to: op); beam.addLine(to: sp)
                    ctx.stroke(beam, with: .color(Theme.ember.opacity(0.35)), lineWidth: 6)
                    ctx.stroke(beam, with: .color(.white), lineWidth: 1.2)
                    let f = (t * 0.5).truncatingRemainder(dividingBy: 1)
                    let q = CGPoint(x: op.x + (sp.x - op.x) * f, y: op.y + (sp.y - op.y) * f)
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(.white))
                }
                if !(spv.2 < 0 && (spv.0 * spv.0 + spv.1 * spv.1) < 1) {
                    ctx.fill(Path(ellipseIn: CGRect(x: sp.x - 16, y: sp.y - 16, width: 32, height: 32)),
                             with: .radialGradient(Gradient(colors: [Theme.ember.opacity(0.9), .clear]), center: sp, startRadius: 0, endRadius: 16))
                    ctx.fill(Path(ellipseIn: CGRect(x: sp.x - 4, y: sp.y - 4, width: 8, height: 8)), with: .color(.white))
                    ctx.draw(Text(g.name).font(.caption2.weight(.bold)).foregroundStyle(.white), at: CGPoint(x: sp.x, y: sp.y - 16))
                }
            }
            if ov.2 > 0 {
                let pulse = CGFloat(0.5 + 0.5 * sin(t * 2.2))
                ctx.stroke(Path(ellipseIn: CGRect(x: op.x - 7 - 7 * pulse, y: op.y - 7 - 7 * pulse, width: 14 + 14 * pulse, height: 14 + 14 * pulse)), with: .color(Theme.good.opacity(0.6 * (1 - Double(pulse)))), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: op.x - 4.5, y: op.y - 4.5, width: 9, height: 9)), with: .color(Theme.good))
                ctx.stroke(Path(ellipseIn: CGRect(x: op.x - 4.5, y: op.y - 4.5, width: 9, height: 9)), with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    /// Adds a (lat, lon) polyline to `path`, breaking it wherever it passes behind the globe.
    private func addLine(_ path: inout Path, _ pts: [(Double, Double)], _ cam: Cam, _ pt: ((Double, Double, Double)) -> CGPoint) {
        var pen = false
        for (lat, lon) in pts {
            let u = unit(lat, lon)
            let v = cam.project(u.0, u.1, u.2)
            if v.2 > 0 { let p = pt(v); pen ? path.addLine(to: p) : path.move(to: p); pen = true } else { pen = false }
        }
    }
}
