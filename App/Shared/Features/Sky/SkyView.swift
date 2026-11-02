import SwiftUI
import StarlinkKit

struct SkyView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var model = SkyModel()
    enum Mode: Hashable { case globe, chart, list }
    @State private var mode: Mode = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-skymode"), i + 1 < a.count { return a[i + 1] == "chart" ? .chart : a[i + 1] == "list" ? .list : .globe }
        return .globe
    }()
    @State private var latText = ""
    @State private var lonText = ""

    private var boresight: (az: Double, el: Double)? {
        if let g = model.snapshot?.connected, session.source == .demo { return (g.satellite.azimuth, g.satellite.elevation) }
        if let a = session.dishStatus?.azimuthDeg, let e = session.dishStatus?.elevationDeg { return (a, e) }
        return nil
    }

    var body: some View {
        VStack(spacing: Theme.spacing) {
            if model.observer == nil { locationCard } else { content }
            Text("\(model.dataNote) Satellite elements: CelesTrak. Positions are computed on your device; the connected satellite is inferred from where the dish points.")
                .font(.caption2).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center).padding(.horizontal, 8)
        }
        .task { model.start(session: session) }
        .onDisappear { model.stop() }
        .onChange(of: session.source) { _, _ in model.stop(); model.start(session: session) }
    }

    @ViewBuilder private var content: some View {
        let snap = model.snapshot
        HStack(spacing: 12) {
            stat("\(snap?.inView.count ?? 0)", "in view", tint: Theme.signal)
            stat("\(snap?.aboveHorizon ?? 0)", "above horizon", tint: .white)
            stat(model.totalSatellites.formatted(), "in orbit", tint: Theme.dust)
        }
        PillPicker(options: [(Mode.globe, "Globe"), (.chart, "Sky chart"), (.list, "Satellites")], selection: $mode)
        Group {
            switch mode {
            case .globe: GlobeView(snapshot: snap, observer: model.observer).frame(height: 420)
            case .chart: SkyChartView(snapshot: snap, boresight: boresight, trail: model.trail).frame(maxWidth: 520).padding(8)
            case .list: satelliteList(snap)
            }
        }
        .padding(mode == .list ? 0 : 6).frame(maxWidth: .infinity).card()
        connectedCard
        timeControl
        locationRow
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.numeral(28)).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var connectedCard: some View {
        if let g = model.snapshot?.connected {
            let s = g.satellite
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(session.source == .demo ? "Example connection" : "Probably connected", systemImage: "dot.radiowaves.up.forward").font(.headline)
                    Spacer()
                    Text(g.confidence.rawValue.capitalized + " match").font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
                        .background((g.confidence == .high ? Theme.good : g.confidence == .medium ? Theme.warn : Theme.bad).opacity(0.25), in: Capsule())
                }
                Text(s.name).font(.wide(24, weight: .bold))
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow { kv("Elevation", String(format: "%.0f°", s.elevation)); kv("Azimuth", String(format: "%.0f° %@", s.azimuth, compass(s.azimuth))) }
                    GridRow { kv("Distance", "\(Int(s.rangeKm)) km"); kv("Altitude", "\(Int(s.altitudeKm)) km") }
                    GridRow { kv("Speed", String(format: "%.1f km/s", s.speedKmS)); kv("Orbit tilt", String(format: "%.1f°", s.inclinationDeg)) }
                }
                if let t = model.leavesIn { Text("Leaves your dish's view in about \(t < 90 ? "\(Int(t)) seconds" : "\(Int((t / 60).rounded())) minutes"), then the dish hands over to the next satellite.").font(.footnote).foregroundStyle(.secondary) }
                Text("Starlink doesn't publish which satellite a dish is using. Perigee finds the one closest to the direction your dish reports it is pointing (\(String(format: "%.1f", g.separationDeg))° away).")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.ember)
        } else if model.observer != nil, session.source == .live, boresight == nil {
            Label("Connect to your dish to see which satellite it's using.", systemImage: "antenna.radiowaves.left.and.right.slash").font(.footnote).foregroundStyle(.secondary)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) { Text(k).foregroundStyle(.secondary); Text(v).font(.body.monospacedDigit()) }.font(.subheadline)
    }
    private func compass(_ az: Double) -> String { ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int(((az + 22.5).truncatingRemainder(dividingBy: 360)) / 45)] }

    private func satelliteList(_ snap: ConstellationSnapshot?) -> some View {
        VStack(spacing: 0) {
            ForEach((snap?.inView ?? []).prefix(40)) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) { Text(s.name).font(.subheadline.weight(.semibold))
                            if snap?.connected?.satellite.id == s.id { Text("Connected?").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.ember.opacity(0.3), in: Capsule()) } }
                        Text("\(Int(s.altitudeKm)) km · \(Int(s.rangeKm)) km away").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f° el", s.elevation)).font(.body.monospacedDigit())
                    Text(String(format: "%03.0f° az", s.azimuth)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }.padding(.horizontal, 14).padding(.vertical, 10)
                Divider().overlay(.white.opacity(0.08))
            }
            if (snap?.inView.isEmpty ?? true) { Text("No satellites in view right now.").foregroundStyle(.secondary).padding(30) }
        }
    }

    private var timeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TIME").eyebrow(); Spacer()
                Text(model.timeOffset == 0 ? "Live" : String(format: "%+.0f min", model.timeOffset / 60)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if model.timeOffset != 0 { Button("Now") { model.timeOffset = 0 }.font(.caption.weight(.bold)).tint(Theme.ember) }
            }
            Slider(value: $model.timeOffset, in: -600...1800, step: 30).tint(Theme.ember)
                .accessibilityLabel("Time offset in minutes")
            Text("Slide forward to watch satellites fly over. The constellation moves about 7.6 km every second.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14).card()
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR LOCATION").eyebrow()
            if let o = model.observer { Text(String(format: "%.3f°, %.3f°", o.latitude, o.longitude)).font(.body.monospacedDigit()) }
            HStack {
                Button { model.useCurrentLocation() } label: { Label("Use my location", systemImage: "location.fill") }.buttonStyle(.bordered).tint(Theme.ember)
                Button("Edit manually") { model.observer = nil }.buttonStyle(.bordered).tint(.white)
            }
            if let s = model.locationStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
            Text("Your coordinates stay on this device. Starlink's local API doesn't share the dish's GPS position.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("MarsOrbit").resizable().scaledToFill().frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).accessibilityHidden(true)
            Label("Where are you?", systemImage: "location.circle.fill").font(.headline)
            Text("To work out which satellites are overhead, Perigee needs your position. The dish's own GPS isn't available over the local network, so use this device's location or type it in. It never leaves your device.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { model.useCurrentLocation() } label: { Label("Use my location", systemImage: "location.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(Theme.ember).controlSize(.large)
            HStack {
                TextField("Latitude", text: $latText).textFieldStyle(.roundedBorder)
                TextField("Longitude", text: $lonText).textFieldStyle(.roundedBorder)
                Button("Set") {
                    if let la = Double(latText), let lo = Double(lonText), Observer(latitude: la, longitude: lo).isValid { model.observer = Observer(latitude: la, longitude: lo) }
                    else { model.locationStatus = "Enter latitude (−90…90) and longitude (−180…180) in decimal degrees." }
                }.buttonStyle(.bordered).tint(.white)
            }
            if let s = model.locationStatus { Text(s).font(.footnote).foregroundStyle(Theme.warn) }
        }.padding(16).card()
    }
}

/// Dish tab: status & settings, or the satellites overhead.
struct DishHub: View {
    enum Tab: Hashable { case status, sky }
    @State private var tab: Tab = {
        let a = CommandLine.arguments
        return a.firstIndex(of: "-dishtab").flatMap { i in i + 1 < a.count ? (a[i + 1] == "sky" ? Tab.sky : Tab.status) : nil } ?? .status
    }()
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab == .sky ? "Satellites" : "Dish").font(.wide(28, weight: .bold))
                    Text(tab == .sky ? "What's overhead, and what you're connected to" : "Your dish, its view of the sky and its settings").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                PillPicker(options: [(Tab.status, "Dish"), (.sky, "Satellites")], selection: $tab)
                if tab == .status { DishContent() } else { SkyView() }
            }
            .padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 900)
            .cardGroup()
        }
        .background(ScreenBackground())
        .navigationTitle("Dish")
        .customHeader()
    }
}
