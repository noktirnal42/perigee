import SwiftUI
import Charts
import StarlinkKit

@MainActor @Observable
final class StallRunner {
    var running = false
    var samples: [Double?] = []
    var error: String?
    var result: StallResult?
    let count = 150, interval = 0.2
    private var task: Task<Void, Never>?

    func start(host: String, label: String, session: StarlinkSession) {
        guard !running else { return }
        running = true; samples = []; result = nil; error = nil
        let snapshot = session.settingsSummary
        let n = count, iv = interval
        task = Task {
            do {
                let rtt = try await ICMPPinger().run(host: host, count: n, interval: iv) { s in
                    Task { @MainActor [weak self] in self?.samples = s }
                }
                if Task.isCancelled { running = false; return }
                let r = StallAnalysis.analyze(rtt: rtt, interval: iv, target: host, label: label.isEmpty ? "Run" : label, settings: snapshot)
                result = r
                await session.results.add(r)
                await session.history.addAnnotation(.init(
                    kind: .stallTest, title: label.isEmpty ? "Stall test" : label,
                    detail: "\(r.episodes) stalls · \(String(format: "%.1f", r.lossPercent))% loss · p95 \(Int(r.p95Ms)) ms"))
                Haptics.success()
            } catch { self.error = error.localizedDescription }
            running = false
        }
    }
    func cancel() { task?.cancel(); running = false }
}

struct DiagnosticsView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var runner = StallRunner()
    @State private var target = "192.168.1.1"
    @State private var label = ""
    @State private var saved: [StallResult] = []
    @State private var compare: [UUID] = []
    @State private var showCompare = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics").font(.wide(28, weight: .bold))
                    Text("Measure, change one thing, measure again").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                tester
                if let r = runner.result { ResultSummary(result: r) }
                history
                tools
                CapabilitiesCard()
                ExportCard(results: saved)
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 900)
            .cardGroup()
        }
        .background(ScreenBackground())
        .navigationTitle("Diagnostics")
        .customHeader()
        .task(id: runner.result?.id) { saved = await session.results.results }
        .sheet(isPresented: $showCompare) { NavigationStack { CompareView(results: saved.filter { compare.contains($0.id) }) }.presentationDetents([.large]) }
    }

    private var tester: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Stall tester", systemImage: "waveform.path.ecg").font(.headline)
            Text("Sends 150 pings over 30 seconds and counts every freeze. Run it, change one setting in Tune, run it again, then compare.").font(.footnote).foregroundStyle(.secondary)
            Picker("Target", selection: $target) {
                Text("Router").tag(session.routerHost); Text("Dish").tag(session.dishHost); Text("Internet").tag("1.1.1.1")
            }.pickerStyle(.segmented).disabled(runner.running)
            Text(target == session.routerHost ? "Router: measures your Wi-Fi hop only." : target == session.dishHost ? "Dish: Wi-Fi hop plus the wired link to the dish." : "Internet: everything, through Starlink to Cloudflare.").font(.caption).foregroundStyle(.secondary)
            TextField("Label this run (e.g. “ch149 80MHz”)", text: $label).textFieldStyle(.roundedBorder).disabled(runner.running)

            if runner.running || !runner.samples.isEmpty && runner.result == nil { LiveStrip(samples: runner.samples, total: runner.count) }
            HStack {
                if runner.running {
                    ProgressView(value: Double(runner.samples.count), total: Double(runner.count)).tint(Theme.ember)
                    Button("Stop") { runner.cancel() }.buttonStyle(.bordered).tint(.white)
                } else {
                    Button { runner.start(host: target, label: label, session: session) } label: { Label("Start 30 s test", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.ember).controlSize(.large)
                }
            }
            if let e = runner.error { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
            if session.source == .demo { Text("Demo mode pings are real network pings to the addresses above, not simulated.").font(.caption).foregroundStyle(.tertiary) }
        }.padding(16).card()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Saved runs")
            if saved.isEmpty { Text("Your finished tests appear here.").foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity).card() }
            else {
                VStack(spacing: 0) {
                    ForEach(saved) { r in
                        HStack(spacing: 12) {
                            Button { toggle(r.id) } label: { Image(systemName: compare.contains(r.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(compare.contains(r.id) ? Theme.ember : .secondary) }
                                .buttonStyle(.plain).accessibilityLabel("Select \(r.label) for comparison")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(.subheadline.weight(.semibold))
                                Text("\(r.episodes) stalls · \(String(format: "%.1f", r.lossPercent))% loss · p95 \(Int(r.p95Ms)) ms").font(.caption).foregroundStyle(.secondary)
                                if let s = r.settings?.summary { Text(s).font(.caption2).foregroundStyle(.tertiary) }
                            }
                            Spacer()
                            Text(r.verdict.headline).font(.caption.weight(.bold)).foregroundStyle(color(r.verdict.grade))
                            Button(role: .destructive) { Task { await session.results.remove(r.id); saved = await session.results.results; compare.removeAll { $0 == r.id } } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        }.padding(14)
                        if r.id != saved.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }.card()
                HStack {
                    Button { showCompare = true } label: { Label("Compare \(compare.count) selected", systemImage: "chart.bar.xaxis") }
                        .buttonStyle(.borderedProminent).tint(Theme.ember).disabled(compare.count < 2)
                    Text(compare.count < 2 ? "Pick two or more runs." : "").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggle(_ id: UUID) { if let i = compare.firstIndex(of: id) { compare.remove(at: i) } else { compare.append(id) } }
    private func color(_ g: StallVerdict.Grade) -> Color { switch g { case .great: Theme.good; case .ok: Theme.info; case .poor: Theme.warn; case .bad: Theme.bad } }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Router tools")
            VStack(spacing: 0) {
                NavigationLink { SpeedAndTraceView() } label: { toolRow("speedometer", "Speed test & traceroute", "Status of the router's own tests") }
                Divider().overlay(.white.opacity(0.08)).padding(.leading, 56)
                NavigationLink { LogView() } label: { toolRow("doc.text.magnifyingglass", "System log", "Recent router log lines") }
            }.card()
        }
    }
    private func toolRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 30).foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.medium)); Text(sub).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(14).contentShape(Rectangle()).foregroundStyle(.white)
    }
}

struct LiveStrip: View {
    let samples: [Double?]
    let total: Int
    var body: some View {
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { i, v in
                BarMark(x: .value("n", i), y: .value("ms", min(v ?? 100, 100)), width: .fixed(2))
                    .foregroundStyle((v == nil || v! > 20) ? Theme.bad : Theme.good)
            }
        }
        .chartXScale(domain: 0...total).chartYScale(domain: 0...100).chartXAxis(.hidden)
        .chartYAxis { AxisMarks(values: [0, 20, 50, 100]) { AxisValueLabel().foregroundStyle(.secondary) } }
        .frame(height: 100)
        .accessibilityLabel("Live ping chart, \(samples.count) of \(total) samples")
    }
}

struct ResultSummary: View {
    let result: StallResult
    var body: some View {
        let v = result.verdict
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(v.headline).font(.wide(22, weight: .bold)); Spacer(); Text(result.label).font(.caption).foregroundStyle(.secondary) }
            Text(v.detail).font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                m("Loss", String(format: "%.1f%%", result.lossPercent)); m("Median", String(format: "%.1f ms", result.medianMs)); m("p95", String(format: "%.0f ms", result.p95Ms))
                m("Max", String(format: "%.0f ms", result.maxMs)); m("Stalls", "\(result.episodes)"); m("Every", result.averageGapSeconds.map { String(format: "%.1f s", $0) } ?? "—")
            }
            LiveStrip(samples: result.rttMs, total: result.rttMs.count)
        }.padding(16).card(tint: v.grade == .great ? Theme.good : v.grade == .bad ? Theme.bad : nil)
    }
    private func m(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(t).font(.caption).foregroundStyle(.secondary); Text(v).font(.numeral(22)).minimumScaleFactor(0.7).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    let results: [StallResult]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                chart("Stalls (fewer is better)", \.episodesD)
                chart("Packet loss % ", \.lossPercent)
                chart("p95 latency (ms)", \.p95Ms)
                VStack(alignment: .leading, spacing: 8) {
                    Text("LATENCY OVER THE RUN").eyebrow()
                    Chart {
                        ForEach(results) { r in
                            ForEach(Array(r.rttMs.enumerated()), id: \.offset) { i, v in
                                LineMark(x: .value("s", Double(i) * r.interval), y: .value("ms", min(v ?? 150, 150)), series: .value("run", r.label)).foregroundStyle(by: .value("Run", r.label))
                            }
                        }
                    }.chartXAxisLabel("seconds").frame(height: 200)
                }.padding(16).card()
                if let a = results.first, let b = results.last, a.id != b.id {
                    let d = a.episodes - b.episodes
                    Text(d == 0 ? "Both runs stalled the same number of times." : "“\(d < 0 ? a.label : b.label)” had \(abs(d)) fewer stall\(abs(d) == 1 ? "" : "s") than “\(d < 0 ? b.label : a.label)”.")
                        .font(.headline).padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                }
                ForEach(results) { r in
                    if let s = r.settings?.summary { Text("\(r.label): \(s)").font(.footnote).foregroundStyle(.secondary) }
                }
            }.padding(16).frame(maxWidth: 800)
            .cardGroup()
        }
        .background(ScreenBackground()).navigationTitle("A/B comparison")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func chart(_ title: String, _ value: KeyPath<StallResult, Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).eyebrow()
            Chart(results) { r in
                BarMark(x: .value("Run", r.label), y: .value(title, r[keyPath: value])).foregroundStyle(by: .value("Run", r.label))
                    .annotation(position: .top) { Text(String(format: r[keyPath: value] < 10 ? "%.1f" : "%.0f", r[keyPath: value])).font(.caption2) }
            }.chartLegend(.hidden).frame(height: 130)
        }.padding(16).card()
    }
}
private extension Int { var doubleValue: Double { Double(self) } }
private extension StallResult { var episodesD: Double { Double(episodes) } }

struct CapabilitiesCard: View {
    @Environment(StarlinkSession.self) private var session
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("What this connection allows")
            VStack(spacing: 0) {
                ForEach(session.capabilities) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(c.state)).foregroundStyle(tint(c.state)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(c.title) · \(c.device == .router ? "router" : "dish")").font(.subheadline.weight(.medium))
                            Text(c.state == .available ? c.detail : c.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(12)
                    if c.id != session.capabilities.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
                if session.capabilities.isEmpty { Text("Checks run once a device answers.").foregroundStyle(.secondary).padding(20) }
            }.card()
            Text("Perigee never calls authentication, signing, debug, factory or test-mode methods. Those need Starlink's own credentials and are blocked in code.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
    private func icon(_ s: CapabilityState) -> String { switch s { case .available: "checkmark.circle.fill"; case .denied: "lock.fill"; case .unsupported: "xmark.circle"; case .unknown: "circle.dotted"; case .failed: "exclamationmark.triangle.fill" } }
    private func tint(_ s: CapabilityState) -> Color { switch s { case .available: Theme.good; case .denied: Theme.warn; case .unsupported: .secondary; case .unknown: .secondary; case .failed: Theme.bad } }
}

struct ExportCard: View {
    @Environment(StarlinkSession.self) private var session
    let results: [StallResult]
    var body: some View {
        ShareLink(item: report, subject: Text("Perigee report"), message: Text("Network report from Perigee")) {
            Label("Export report", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6)
        }.buttonStyle(.bordered).tint(.white)
    }
    /// Plain-text report. Contains no Wi-Fi passwords and masks MAC addresses.
    var report: String {
        var s = "PERIGEE REPORT · \(Date().formatted())\n\n"
        if let r = session.routerStatus { s += "Router: \(r.identity.hardwareVersion) fw \(r.identity.softwareVersion), up \(Fmt.uptime(r.identity.uptime)), ping \(Fmt.ms(r.internetPingMs)) ms\n" }
        if let d = session.dishStatus { s += "Dish: \(d.identity.hardwareVersion) fw \(d.identity.softwareVersion), PoP ping \(Fmt.ms(d.popPingMs)) ms, obstructed \(Fmt.percent(d.obstructionFraction))%\n" }
        for r in session.radios { s += "Radio \(r.band.label): frame errors \(String(format: "%.2f", r.frameErrorRate * 100))%, \(r.temperatureC.map { "\(Int($0))°C" } ?? "")\n" }
        if let t = session.tuning { s += "Config: 5 GHz ch \(t.channel5 == 0 ? "auto" : "\(t.channel5)") \(t.vht5.label), 2.4 GHz ch \(t.channel2 == 0 ? "auto" : "\(t.channel2)"), DFS \(t.dfsEnabled), traffic: \(t.traffic.label)\n" }
        s += "\nSTALL TESTS\n"
        for r in results { s += "- \(r.label) → \(r.target): \(r.episodes) stalls, \(String(format: "%.1f", r.lossPercent))% loss, median \(String(format: "%.1f", r.medianMs)) ms, p95 \(Int(r.p95Ms)) ms (\(r.verdict.headline))\n" }
        s += "\nCHANGES THIS SESSION\n"
        for c in session.changeLog { s += "- \(c.title): \(c.from) → \(c.to)\(c.verified ? "" : " (unverified)")\n" }
        s += "\nGenerated by Perigee, an unofficial companion app.\n"
        return s
    }
}

struct SpeedAndTraceView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var speed: SpeedtestState?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Router speed test", systemImage: "speedometer").font(.headline)
                    if let s = speed {
                        Text(s.running ? "A test is running…" : "No test running.").foregroundStyle(.secondary)
                        if let d = s.downMbps { Text("Down \(Fmt.mbps(d)) Mbps").font(.numeral(24)) }
                    } else if session.isDenied("get_speedtest_status") { Text("Not available over the local network.").foregroundStyle(.secondary) }
                    else { ProgressView() }
                    Text("Perigee only reads the router's speed-test status. Run a test from the official app or a browser, then read your number here to size CAKE (use ~90%).").font(.footnote).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Traceroute", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                    if session.isDenied("wifi_get_traceroute_status") {
                        Text("The router doesn't allow traceroute from the local network (PermissionDenied), so Perigee can't run one for you.").foregroundStyle(.secondary)
                        Text("Use Terminal instead:  traceroute 1.1.1.1").font(.footnote.monospaced()).foregroundStyle(Theme.dust)
                    } else { Text("Traceroute is available on this router. Hop results appear after a test starts.").foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            }.padding(16).frame(maxWidth: 700)
            .cardGroup()
        }
        .background(ScreenBackground()).navigationTitle("Speed & trace")
        .task { speed = try? await session.speedtest() }
    }
}

struct LogView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var text: String?
    @State private var error: String?
    var body: some View {
        ScrollView {
            if let text { Text(text.isEmpty ? "The log is empty." : text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            else if let error { Text(error).foregroundStyle(.secondary).padding(30) }
            else { ProgressView().padding(40) }
        }
        .background(ScreenBackground()).navigationTitle("System log")
        .task {
            do { text = String(try await session.syslog().suffix(20000)) } catch { self.error = (error as? DeviceError)?.isPermissionDenied == true ? "The router doesn't share its log over the local network." : error.localizedDescription }
        }
    }
}
