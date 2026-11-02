import SwiftUI
import StarlinkKit

struct HomeView: View {
    @Environment(StarlinkSession.self) private var session
    @Binding var selection: AppSection
    @State private var showSettings = false

    private var heroState: HeroState {
        switch session.link {
        case .connecting: .connecting
        case .online: .online
        case .degraded: .degraded
        case .offline: .offline
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                ZStack(alignment: .top) {
                    HeroScene(state: heroState, dishTilt: session.dishStatus?.tiltDeg ?? 24, statusText: statusText)
                        .frame(height: 330)
                    header
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))

                VStack(spacing: Theme.spacing) {
                    if case .offline(let why) = session.link { OfflineCard(reason: why) }
                    networkCard
                    alertsBanner
                    ForecastCard()
                    tiles
                    gamingCheck
                    if let t = session.lastUpdated {
                        Text("Updated \(Fmt.time(t)) · \(session.source == .demo ? "demo data" : "live from your router & dish")")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4)).padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .frame(maxWidth: 900)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(ScreenBackground())
        .refreshable { await session.refreshNow() }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() }.presentationDetents([.large]) }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var statusText: String? {
        switch session.link {
        case .degraded(let s): s
        case .offline: "Not connected"
        default: nil
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PERIGEE").font(.wide(22, weight: .bold)).tracking(3).foregroundStyle(.white)
                Text(session.routerStatus.map { "Router \($0.identity.softwareVersion.prefix(10))" } ?? "Starlink companion")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            #if os(iOS)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.headline).frame(width: 40, height: 40).card(radius: 20)
            }.buttonStyle(.plain).accessibilityLabel("Settings")
            #endif
        }
        .padding(.horizontal, 20).padding(.top, 62)
    }

    private var networkCard: some View {
        Button { selection = .network } label: {
            HStack(spacing: 14) {
                Image(systemName: "wifi").font(.title3).frame(width: 44, height: 44).background(Theme.ember.opacity(0.2), in: Circle()).foregroundStyle(Theme.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.ssid ?? "Your network").font(.headline)
                    Text("\(session.wirelessClients.count) devices").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14).card().contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .accessibilityLabel("\(session.ssid ?? "Network"), \(session.wirelessClients.count) devices")
        .accessibilityHint("Opens the network screen")
    }

    @ViewBuilder private var alertsBanner: some View {
        let alerts = (session.routerStatus?.alerts ?? []).map { ("Router", $0) } + (session.dishStatus?.alerts ?? []).map { ("Dish", $0) }
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(alerts.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                        Text("\(alerts[i].0): \(alerts[i].1)").font(.subheadline)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.warn)
            .accessibilityElement(children: .combine)
        }
    }

    private var tiles: some View {
        let cols = [GridItem(.adaptive(minimum: 165, maximum: 300), spacing: 12)]
        let lat = Fmt.downsample(Array((session.routerHistory?.latencyMs ?? []).suffix(900)), to: 60)
        let dl = Fmt.downsample((session.dishHistory?.downlinkBps ?? []).suffix(900).map { Optional($0 / 1e6) }, to: 60)
        let obstructed = session.dishStatus?.obstructionFraction
        let down = Fmt.rate(session.dishStatus?.downlinkBps ?? 0)
        let up = Fmt.rate(session.dishStatus?.uplinkBps ?? 0)
        let ps = session.pingSuccess
        return LazyVGrid(columns: cols, spacing: 12) {
            StatTile(title: "Ping success", value: Fmt.percent(ps), unit: "%", caption: "last 15 minutes",
                     series: Fmt.downsample((session.routerHistory?.dropRate ?? []).suffix(900).map { $0.map { 1 - $0 } }, to: 60),
                     tint: Theme.good, health: ps.map { $0 > 0.99 ? .good : $0 > 0.95 ? .fair : .poor }, domain: 0.8...1.0)
            StatTile(title: "Latency", value: Fmt.ms(session.routerStatus?.internetPingMs ?? session.medianLatency), unit: "ms",
                     caption: "last 15 minutes", series: lat.isEmpty ? session.recentPing : lat, tint: Theme.signal)
            StatTile(title: "Jitter", value: Fmt.ms(session.jitter), unit: "ms", caption: "avg. change between pings",
                     series: zip(lat, lat.dropFirst()).map { abs($1 - $0) }, tint: Theme.warn, health: session.jitter.map { $0 < 6 ? .good : $0 < 15 ? .fair : .poor })
            StatTile(title: "Download", value: down.0, unit: down.1, caption: "dish, right now", series: dl, tint: Theme.info)
            StatTile(title: "Upload", value: up.0, unit: up.1, caption: "dish, right now", tint: Theme.dust)
            StatTile(title: "Obstructed", value: obstructed.map { String(format: "%.1f", $0 * 100) } ?? "—", unit: "%",
                     caption: "of the sky view", tint: Theme.ember,
                     health: obstructed.map { $0 < 0.01 ? .good : $0 < 0.05 ? .fair : .poor })
            StatTile(title: "Router uptime", value: session.routerStatus.map { Fmt.uptime($0.identity.uptime) } ?? "—", caption: "since last restart")
            StatTile(title: "Dish uptime", value: session.dishStatus.map { Fmt.uptime($0.identity.uptime) } ?? "—", caption: "since last restart")
        }
    }

    @ViewBuilder private var gamingCheck: some View {
        if let t = session.tuning {
            let recs = Advisor.channelAdvice(tuning: t, airtime5: session.routerStatus?.airtime5, radio5: session.radios.first { $0.band == .ghz5 })
            let r5 = session.radios.first { $0.band == .ghz5 }
            let radio = r5.map(Advisor.radio)
            Button { selection = .tune } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Gaming check", systemImage: "gamecontroller.fill").font(.headline)
                        Spacer()
                        Text(recs.isEmpty ? "All good" : "\(recs.count) tip\(recs.count == 1 ? "" : "s")")
                            .font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
                            .background((recs.isEmpty ? Theme.good : Theme.ember).opacity(0.25), in: Capsule())
                    }
                    if let radio {
                        HStack(spacing: 8) {
                            HealthDot(health: radio.health)
                            Text("5 GHz radio: \(radio.headline)").font(.subheadline)
                        }
                    }
                    if let first = recs.first {
                        Text(first.title).font(.subheadline.weight(.semibold))
                        Text(first.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Your Wi-Fi settings already follow the recommended setup for low-latency gaming.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.ember).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.white)
        }
    }
}

struct OfflineCard: View {
    @Environment(StarlinkSession.self) private var session
    let reason: OfflineReason
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("PlanetRing").resizable().scaledToFill().frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).opacity(0.85).accessibilityHidden(true)
            Label(reason.title, systemImage: "wifi.slash").font(.headline)
            Text(reason.advice).font(.subheadline).foregroundStyle(.secondary)
            if let e = session.lastError { Text(e).font(.caption).foregroundStyle(.white.opacity(0.45)) }
            HStack {
                Button("Retry") { session.reconnect() }.buttonStyle(.borderedProminent).tint(Theme.ember)
                Button("Try demo mode") { session.setSource(.demo) }.buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.bad)
    }
}
