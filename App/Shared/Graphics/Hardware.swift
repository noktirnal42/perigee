import SwiftUI

/// Original vector "renders" of a flat-panel dish and a puck router. Shaded with gradients to read as 3D.
struct DishRender: View {
    var tilt: Double = 24          // degrees; drives the visible lean
    var glow: Color = Theme.signal

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let c = CGPoint(x: w / 2, y: h * 0.42)
            let pw = w * 0.74, ph = h * 0.46
            let lean = CGFloat(tilt / 90) * w * 0.10

            // Mast + foot
            var mast = Path()
            mast.move(to: CGPoint(x: c.x - 4, y: c.y + ph * 0.42)); mast.addLine(to: CGPoint(x: c.x + 4, y: c.y + ph * 0.42))
            mast.addLine(to: CGPoint(x: c.x + 7, y: h * 0.9)); mast.addLine(to: CGPoint(x: c.x - 7, y: h * 0.9)); mast.closeSubpath()
            ctx.fill(mast, with: .linearGradient(Gradient(colors: [.white.opacity(0.95), Color(white: 0.62)]),
                                                 startPoint: CGPoint(x: c.x - 7, y: 0), endPoint: CGPoint(x: c.x + 7, y: 0)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.2, y: h * 0.86, width: w * 0.4, height: h * 0.08)),
                     with: .linearGradient(Gradient(colors: [.white, Color(white: 0.6)]), startPoint: CGPoint(x: 0, y: h * 0.86), endPoint: CGPoint(x: 0, y: h * 0.94)))

            // Panel (perspective parallelogram with thickness)
            let tl = CGPoint(x: c.x - pw / 2 + lean, y: c.y - ph / 2)
            let tr = CGPoint(x: c.x + pw / 2 + lean, y: c.y - ph / 2 + 6)
            let br = CGPoint(x: c.x + pw / 2 - lean * 0.3, y: c.y + ph / 2)
            let bl = CGPoint(x: c.x - pw / 2 - lean * 0.3, y: c.y + ph / 2 - 6)
            let depth: CGFloat = 9
            var edge = Path()
            edge.move(to: bl); edge.addLine(to: br); edge.addLine(to: CGPoint(x: br.x, y: br.y + depth)); edge.addLine(to: CGPoint(x: bl.x, y: bl.y + depth)); edge.closeSubpath()
            ctx.fill(edge, with: .color(Color(white: 0.58)))
            var side = Path()
            side.move(to: tr); side.addLine(to: br); side.addLine(to: CGPoint(x: br.x, y: br.y + depth)); side.addLine(to: CGPoint(x: tr.x + 3, y: tr.y + depth)); side.closeSubpath()
            ctx.fill(side, with: .color(Color(white: 0.72)))
            var face = Path()
            face.move(to: tl); face.addLine(to: tr); face.addLine(to: br); face.addLine(to: bl); face.closeSubpath()
            ctx.fill(face, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.86), Color(white: 0.74)]),
                                                 startPoint: tl, endPoint: br))
            ctx.stroke(face, with: .color(.white.opacity(0.9)), lineWidth: 1)

            // Phased-array hex lattice, clipped to the face
            var clipped = ctx
            clipped.clip(to: face)
            let step: CGFloat = max(10, w / 16)
            var y: CGFloat = tl.y
            var row = 0
            while y < br.y + step {
                var x = tl.x - step + (row % 2 == 0 ? 0 : step / 2)
                while x < tr.x + step {
                    clipped.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: step * 0.62, height: step * 0.62)),
                                   with: .color(Color(white: 0.55).opacity(0.28)), lineWidth: 0.7)
                    x += step
                }
                y += step * 0.78; row += 1
            }
            // specular sweep
            clipped.fill(Path(CGRect(x: tl.x, y: tl.y, width: pw * 0.35, height: ph)),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .clear]), startPoint: tl, endPoint: CGPoint(x: tl.x + pw * 0.35, y: tl.y + 20)))
            // status LED
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y + ph / 2 - 12, width: 6, height: 6)), with: .color(glow))
        }
        .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
        .accessibilityHidden(true)
    }
}

struct RouterRender: View {
    var led: Color = Theme.good
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let rx = w * 0.40, ry = rx * 0.34
            let cx = w / 2, topY = h * 0.30, bodyH = h * 0.36
            // ground shadow
            ctx.fill(Path(ellipseIn: CGRect(x: cx - rx * 1.1, y: topY + bodyH - ry * 0.4, width: rx * 2.2, height: ry * 1.5)),
                     with: .radialGradient(Gradient(colors: [.black.opacity(0.5), .clear]), center: CGPoint(x: cx, y: topY + bodyH + ry * 0.3), startRadius: 0, endRadius: rx * 1.1))
            // side wall
            var body = Path()
            body.move(to: CGPoint(x: cx - rx, y: topY))
            body.addLine(to: CGPoint(x: cx - rx, y: topY + bodyH))
            body.addQuadCurve(to: CGPoint(x: cx + rx, y: topY + bodyH), control: CGPoint(x: cx, y: topY + bodyH + ry * 2))
            body.addLine(to: CGPoint(x: cx + rx, y: topY))
            body.closeSubpath()
            ctx.fill(body, with: .linearGradient(Gradient(stops: [
                .init(color: Color(white: 0.62), location: 0), .init(color: .white, location: 0.35),
                .init(color: Color(white: 0.9), location: 0.6), .init(color: Color(white: 0.55), location: 1)]),
                                                 startPoint: CGPoint(x: cx - rx, y: 0), endPoint: CGPoint(x: cx + rx, y: 0)))
            // top cap
            let top = CGRect(x: cx - rx, y: topY - ry, width: rx * 2, height: ry * 2)
            ctx.fill(Path(ellipseIn: top), with: .linearGradient(Gradient(colors: [.white, Color(white: 0.84)]),
                                                                 startPoint: CGPoint(x: top.minX, y: top.minY), endPoint: CGPoint(x: top.maxX, y: top.maxY)))
            ctx.stroke(Path(ellipseIn: top.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: 1)
            // inset vent ring
            ctx.stroke(Path(ellipseIn: top.insetBy(dx: rx * 0.34, dy: ry * 0.34)), with: .color(Color(white: 0.7).opacity(0.5)), lineWidth: 1)
            // LED band on the lip
            var led = Path()
            led.addEllipse(in: CGRect(x: cx - rx * 0.5, y: topY + ry * 0.7, width: rx, height: 5))
            ctx.fill(led, with: .color(self.led))
            ctx.fill(led, with: .radialGradient(Gradient(colors: [self.led.opacity(0.6), .clear]), center: CGPoint(x: cx, y: topY + ry * 0.7 + 2), startRadius: 0, endRadius: rx * 0.7))
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
        .accessibilityHidden(true)
    }
}
