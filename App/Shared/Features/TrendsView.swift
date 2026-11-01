import SwiftUI
import Charts
import StarlinkKit

enum TrendRange: String, CaseIterable, Identifiable, Hashable {
    case day, week, month
    var id: String { rawValue }
    var label: String { switch self { case .day: "24h"; case .week: "7d"; case .month: "30d" } }
    var since: Date {
        switch self {
        case .day: Date().addingTimeInterval(-86400)
        case .week: Date().addingTimeInterval(-7 * 86400)
        case .month: Date().addingTimeInterval(-30 * 86400)
        }
    }
    var resolution: HistoryResolution { switch self { case .day: .minute; case .week: .hour; case .month: .day } }
}

/// Long-term trends: unlike the device's own 15-minute buffer, this reads from Perigee's own on-device
/// history store, so "what did last night look like" has a real answer.
struct TrendsView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var range: TrendRange = .day
    @State private var buckets: [HistoryBucket] = []
    @State private var annotations: [HistoryAnnotation] = []
    @State private var uptime: Double?
    @State private var loaded = false
    @State private var recap: WeeklyRecap?
    @State private var recentAlerts: [TriggeredAlert] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trends").font(.wide(28, weight: .bold))
                    Text("What your network has been doing").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                PillPicker(options: TrendRange.allCases.map { ($0, $0.label) }, selection: $range)

                if let recap { recapCard(recap) }
                if !recentAlerts.isEmpty { recentAlertsCard }

                if !loaded {
                    ProgressView().padding(40).frame(maxWidth: .infinity)
                } else if buckets.isEmpty {
                    Text("Not enough history yet for this range. Keep Perigee open or running in the background and check back.")
                        .foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).card()
                } else {
                    uptimeTile
                    pingChart
                    obstructionChart
                }
                timeline
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 900)
        }
        .background(ScreenBackground())
        .navigationTitle("Trends")
        .customHeader()
        .task(id: range) { await reload() }
        .task {
            recap = await WeeklyRecap.compute(from: session.history)
            recentAlerts = Array(await session.automation.fired.prefix(5))
        }
    }

    private func reload() async {
        loaded = false
        let since = range.since
        async let b = session.history.buckets(resolution: range.resolution, since: since)
        async let a = session.history.annotations(since: since)
        async let u = session.history.uptimeFraction(since: since)
        buckets = await b
        annotations = await a
        uptime = await u
        loaded = true
    }

    private func recapCard(_ r: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Weekly recap", systemImage: "calendar").font(.headline)
            Text(r.summary).font(.subheadline).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var recentAlertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Recent alerts")
            VStack(spacing: 0) {
                ForEach(recentAlerts) { a in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bell.badge.fill").foregroundStyle(Theme.warn).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.subheadline.weight(.medium))
                            Text(a.message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.relative(a.date)).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(12)
                    if a.id != recentAlerts.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }.card()
        }
    }

    private var uptimeTile: some View {
        StatTile(title: "Uptime", value: uptime.map { String(format: "%.2f", $0 * 100) } ?? "—", unit: "%",
                 caption: "\(range.label) · both router & dish answering", tint: Theme.good)
    }

    private var pingChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ping (ms)").eyebrow()
            Chart {
                ForEach(buckets) { b in
                    if let lo = b.minPingMs, let hi = b.maxPingMs {
                        AreaMark(x: .value("Time", b.start), yStart: .value("min", lo), yEnd: .value("max", hi))
                            .foregroundStyle(Theme.signal.opacity(0.16))
                    }
                    if let avg = b.avgPingMs {
                        LineMark(x: .value("Time", b.start), y: .value("ms", avg)).foregroundStyle(Theme.signal)
                    }
                }
                ForEach(annotations) { a in
                    RuleMark(x: .value("Event", a.date))
                        .foregroundStyle(tint(a.kind).opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 180)
            .accessibilityLabel("Ping trend over \(range.label)")
        }.padding(16).card()
    }

    private var obstructionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Obstruction (%)").eyebrow()
            Chart(buckets) { b in
                if let o = b.avgObstruction {
                    LineMark(x: .value("Time", b.start), y: .value("%", o * 100)).foregroundStyle(Theme.warn)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 140)
            .accessibilityLabel("Obstruction trend over \(range.label)")
        }.padding(16).card()
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Timeline")
            if annotations.isEmpty {
                Text("Tuning changes, dish changes and saved stall tests will show up here.")
                    .foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(annotations) { a in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: icon(a.kind)).foregroundStyle(tint(a.kind)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.subheadline.weight(.medium))
                                if !a.detail.isEmpty { Text(a.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            Text(Fmt.relative(a.date)).font(.caption2).foregroundStyle(.tertiary)
                        }.padding(12)
                        if a.id != annotations.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }.card()
            }
        }
    }

    private func icon(_ k: HistoryAnnotation.Kind) -> String {
        switch k {
        case .tuningChange: "slider.horizontal.3"
        case .dishChange: "antenna.radiowaves.left.and.right"
        case .stallTest: "waveform.path.ecg"
        case .writeRefused: "lock.fill"
        case .custom: "circle"
        }
    }
    private func tint(_ k: HistoryAnnotation.Kind) -> Color {
        switch k {
        case .tuningChange: Theme.ember
        case .dishChange: Theme.info
        case .stallTest: Theme.signal
        case .writeRefused: Theme.warn
        case .custom: .secondary
        }
    }
}
