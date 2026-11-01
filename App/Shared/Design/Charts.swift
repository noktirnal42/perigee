import SwiftUI
import StarlinkKit

/// Minimal sparkline (no axes), drawn with a Canvas so it's cheap enough for lots of tiles.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.signal
    var fill = true
    var domain: ClosedRange<Double>? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = domain?.lowerBound ?? values.min() ?? 0, hi = domain?.upperBound ?? values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height - (size.height - 4) * CGFloat((values[i] - lo) / span) - 2)
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<values.count { line.addLine(to: pt(i)) }
            if fill {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Big-numeral tile with an optional sparkline and caption: "Latency 23 ms · last 15 minutes".
struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var caption: String = ""
    var series: [Double] = []
    var tint: Color = Theme.signal
    var health: Health? = nil
    var domain: ClosedRange<Double>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(.footnote, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                if let health { HealthDot(health: health) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.numeral(34)).foregroundStyle(.white).contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.system(.subheadline, weight: .medium)).foregroundStyle(.white.opacity(0.65)) }
            }
            if series.count > 1 { Sparkline(values: series, tint: tint, domain: domain).frame(height: 30) }
            else { Spacer(minLength: 30) }
            if !caption.isEmpty { Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit). \(caption)")
    }
}

/// Signal-strength bars for RSSI.
struct SignalBars: View {
    let rssi: Double?
    var body: some View {
        let level: Int = { guard let r = rssi else { return 0 }; return r >= -55 ? 4 : r >= -65 ? 3 : r >= -75 ? 2 : r >= -85 ? 1 : 0 }()
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5).fill(i <= level ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 3.5, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel(rssi.map { "Signal \(Int($0)) dBm" } ?? "No signal data")
    }
}
