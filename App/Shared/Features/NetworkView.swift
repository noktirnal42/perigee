import SwiftUI
import Charts
import StarlinkKit

struct NetworkView: View {
    @Environment(StarlinkSession.self) private var session
    enum Tab: Hashable { case devices, nodes, radios, networks }
    @State private var tab: Tab = .devices
    @State private var selected: NetworkClient?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.ssid ?? "Network").font(.wide(28, weight: .bold))
                    Text("\(session.wirelessClients.count) devices connected").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                PillPicker(options: [(.devices, "Devices"), (.nodes, "Nodes"), (.radios, "Radios"), (.networks, "Wi-Fi")], selection: $tab)

                switch tab {
                case .devices: devices
                case .nodes: nodes
                case .radios: radios
                case .networks: networks
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 900)
        }
        .background(ScreenBackground())
        .navigationTitle("Network")
        .customHeader()
        .refreshable { await session.refreshNow() }
        .sheet(item: $selected) { c in NavigationStack { DeviceDetailView(client: c) }.presentationDetents([.large]) }
    }

    // MARK: Devices

    private var devices: some View {
        VStack(spacing: 0) {
            ForEach(session.wirelessClients.sorted { ($0.rx.throughputMbps + $0.tx.throughputMbps) > ($1.rx.throughputMbps + $1.tx.throughputMbps) }) { c in
                Button { selected = c } label: { DeviceRow(client: c) }.buttonStyle(.plain)
                if c.id != session.wirelessClients.last?.id { Divider().overlay(.white.opacity(0.08)).padding(.leading, 66) }
            }
            if session.wirelessClients.isEmpty { Text("No devices yet.").foregroundStyle(.secondary).padding(30) }
        }
        .card()
    }

    private var nodes: some View {
        VStack(spacing: 12) {
            let controllers = session.clients.filter(\.isController)
            ForEach(controllers) { c in
                HStack(spacing: 14) {
                    Image(systemName: "wifi.router.fill").font(.title2).frame(width: 44)
                    VStack(alignment: .leading) {
                        Text("Router").font(.headline)
                        Text(session.routerStatus?.identity.id.replacingOccurrences(of: "Router-", with: "") ?? c.name)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("Main").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3).background(Theme.good.opacity(0.25), in: Capsule())
                }.padding(14).card()
            }
            let meshCount = session.tuning?.meshNodeCount ?? 0
            Image("NodePuck").resizable().scaledToFit().frame(height: 120).frame(maxWidth: .infinity).padding(.vertical, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Label(meshCount == 0 ? "No mesh nodes" : "\(meshCount) mesh node\(meshCount == 1 ? "" : "s")", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Text(meshCount == 0 ? "Add a Starlink mesh node in the official app to extend coverage. Perigee shows them here automatically." : "Backhaul details come from the router's mesh configuration.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    // MARK: Radios

    private var radios: some View {
        VStack(spacing: 12) {
            ForEach(session.radios) { r in RadioCard(radio: r, airtime: r.band == .ghz5 ? session.routerStatus?.airtime5 : session.routerStatus?.airtime2) }
            if session.radios.isEmpty { Text("Radio stats unavailable.").foregroundStyle(.secondary).padding(30).card() }
            Text("Frame errors are counted since the router last restarted. They're a direct read of how much interference the radio is seeing.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    // MARK: Wi-Fi networks

    private var networks: some View {
        VStack(spacing: 12) {
            ForEach(session.tuning?.networks ?? []) { n in NetworkRow(network: n) }
            if (session.tuning?.networks ?? []).isEmpty { Text("Wi-Fi configuration unavailable.").foregroundStyle(.secondary).padding(30).card() }
            if session.isDenied("wifi_get_channels") {
                Label("Channel survey isn't available over the local network, so Perigee can't see neighbouring networks. It uses the router's own airtime counters instead.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
    }
}

struct DeviceRow: View {
    let client: NetworkClient
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 40, height: 40).background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName).font(.headline).lineLimit(1)
                Text(client.vendor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                BandBadge(band: client.band)
                HStack(spacing: 6) {
                    Text("\(Int(client.rx.rateMbps)) Mbps").font(.caption2).foregroundStyle(.secondary)
                    SignalBars(rssi: client.rssi)
                }
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(client.displayName), \(client.band.label), \(Int(client.rx.rateMbps)) megabits per second, signal \(Int(client.rssi ?? 0)) dBm")
    }
    private var icon: String {
        let n = client.displayName.lowercased()
        if n.contains("xbox") { return "gamecontroller.fill" }
        if n.contains("iphone") || n.contains("phone") || n.contains("galaxy") || n.contains("note") { return "iphone" }
        if n.contains("mac") || n.contains("book") { return "laptopcomputer" }
        if n.contains("tv") { return "tv.fill" }
        if n.contains("ipad") { return "ipad" }
        return "wifi"
    }
}

struct RadioCard: View {
    let radio: RadioStat
    let airtime: BandAirtime?
    var body: some View {
        let v = Advisor.radio(radio)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(radio.band.label).font(.headline)
                Spacer()
                HealthDot(health: v.health)
                Text(v.headline).font(.subheadline.weight(.semibold))
            }
            Text(v.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(.white.opacity(0.1))
            HStack(alignment: .top) {
                metric("Frame errors", String(format: "%.2f%%", radio.frameErrorRate * 100))
                metric("Temperature", radio.temperatureC.map { "\(Int($0))°C" } ?? "—")
                metric("Duty cycle", radio.dutyCycle.map { "\(Int($0))%" } ?? "—")
            }
            if !radio.rssi.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RSSI PER ANTENNA").eyebrow()
                    HStack(spacing: 8) {
                        ForEach(radio.rssi.indices, id: \.self) { i in
                            Text("\(Int(radio.rssi[i])) dBm").font(.caption.monospacedDigit()).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            if let a = airtime, a.busy > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AIRTIME").eyebrow()
                    ProgressView(value: min(1, a.busy)) { Text("Channel busy \(Int(a.busy * 100))%  ·  other networks \(Int(a.otherNetworks * 100))%").font(.caption) }
                        .tint(a.busy > 0.5 ? Theme.warn : Theme.good)
                }
            }
        }
        .padding(16).card()
    }
    private func metric(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(t).font(.caption).foregroundStyle(.secondary); Text(v).font(.numeral(20)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NetworkRow: View {
    @Environment(StarlinkSession.self) private var session
    let network: WifiNetworkInfo
    @State private var password: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(network.ssid).font(.headline)
                if network.isGuest { Text("Guest").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.info.opacity(0.25), in: Capsule()) }
                Spacer()
                BandBadge(band: network.band)
            }
            Text("\(network.security)\(network.hidden ? " · hidden" : "")\(network.disabled ? " · off" : "")").font(.footnote).foregroundStyle(.secondary)
            if network.hasPassword {
                HStack {
                    Text(password ?? "••••••••••").font(.body.monospaced())
                    Spacer()
                    Button(password == nil ? "Reveal" : "Hide") { Task { await toggle() } }.buttonStyle(.bordered).tint(.white).controlSize(.small)
                }
                if let error { Text(error).font(.caption).foregroundStyle(Theme.bad) }
            }
        }.padding(14).card()
    }

    private func toggle() async {
        if password != nil { password = nil; return }
        let ok = session.source == .demo ? true : await Biometrics.authenticate(reason: "Reveal the Wi-Fi password for \(network.ssid)")
        guard ok else { error = "Authentication was cancelled."; return }
        error = nil
        do { password = try await session.revealPassword(network: network) } catch { self.error = error.localizedDescription }
    }
}

struct DeviceDetailView: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let client: NetworkClient
    @State private var name = ""
    @State private var history: ClientHistory?
    @State private var saving = false
    @State private var message: String?

    var body: some View {
        let live = session.clients.first { $0.id == client.id } ?? client
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NAME").eyebrow()
                    TextField(live.name.isEmpty ? "Device name" : live.name, text: $name).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save name") { Task { await save(live) } }.buttonStyle(.borderedProminent).tint(Theme.ember)
                            .disabled(!session.writesEnabled || saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        if !session.writesEnabled { Text("Enable writes in Tune to rename.").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()

                if let v = Advisor.client(live) {
                    HStack(alignment: .top, spacing: 10) {
                        HealthDot(health: v.health).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) { Text(v.headline).font(.headline); Text(v.detail).font(.footnote).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                    }.padding(16).card()
                }

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    row("Vendor", live.vendor); row("IP address", live.ip); row("MAC", Fmt.mac(live.mac))
                    row("Band", live.band.label); row("Channel width", "\(live.channelWidthMHz) MHz")
                    row("Signal", live.rssi.map { "\(Int($0)) dBm" } ?? "—"); row("SNR", live.snr.map { "\(Int($0)) dB" } ?? "—")
                    row("Link rate ↓ / ↑", "\(Int(live.rx.rateMbps)) / \(Int(live.tx.rateMbps)) Mbps")
                    row("Streams · MCS", "\(live.rx.nss)×\(live.rx.nss) · MCS \(live.rx.mcs)")
                    row("Connected", Fmt.duration(live.associatedSeconds))
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()

                if let h = history, !h.rxMbps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("THROUGHPUT").eyebrow()
                        Chart {
                            ForEach(Array(h.rxMbps.enumerated()), id: \.offset) { i, v in LineMark(x: .value("t", i), y: .value("Mbps", v), series: .value("d", "Down")).foregroundStyle(Theme.info) }
                            ForEach(Array(h.txMbps.enumerated()), id: \.offset) { i, v in LineMark(x: .value("t", i), y: .value("Mbps", v), series: .value("d", "Up")).foregroundStyle(Theme.ember) }
                        }.chartXAxis(.hidden).frame(height: 140)
                    }.padding(16).card()
                }
            }.padding(16).frame(maxWidth: 700)
        }
        .background(ScreenBackground())
        .navigationTitle(live.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { name = client.givenName; history = try? await session.clientHistory(client) }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v).font(.body.monospacedDigit()).gridColumnAlignment(.trailing) }
    }

    private func save(_ c: NetworkClient) async {
        saving = true; defer { saving = false }
        do { try await session.rename(c, to: name); message = "Saved."; Haptics.success() } catch { message = error.localizedDescription }
    }
}
