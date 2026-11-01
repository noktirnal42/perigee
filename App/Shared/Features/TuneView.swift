import SwiftUI
import StarlinkKit

/// One tunable control, rendered as a row and edited in `ChoiceSheet`.
struct SettingSpec: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let current: WifiSetting
    let options: [Option]
    var danger: String? = nil
    struct Option: Identifiable { let id = UUID(); let setting: WifiSetting; let label: String; var note: String? = nil; var recommended = false }
}

struct TuneView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var editing: SettingSpec?
    @State private var showCake = false
    @State private var preset: TuningPreset?
    @State private var proposed: WifiSetting?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wi-Fi tuning").font(.wide(28, weight: .bold))
                    Text("Settings the official app hides").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)

                WriteModeCard()

                if let t = session.tuning {
                    presets(t)
                    recommendations(t)
                    band(.ghz5, t)
                    band(.ghz2, t)
                    if t.channel5High != 0 || t.mode5High != .default || t.disable5High { band(.ghz5High, t) }
                    general(t)
                    trafficControl(t)
                    network(t)
                    ChangeLogCard()
                } else {
                    ProgressView().padding(40)
                    if session.isDenied("wifi_get_config") { Text("The router refused to share its Wi-Fi configuration.").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 900)
        }
        .background(ScreenBackground())
        .navigationTitle("Tune")
        .customHeader()
        .refreshable { await session.refreshNow() }
        .sheet(item: $editing) { spec in NavigationStack { ChoiceSheet(spec: spec) }.presentationDetents([.large]) }
        .sheet(isPresented: $showCake) { NavigationStack { CakeSheet() }.presentationDetents([.large]) }
        .sheet(item: $preset) { p in NavigationStack { PresetSheet(preset: p) }.presentationDetents([.large]) }
        .sheet(item: Binding(get: { proposed.map { ProposedSetting(setting: $0) } }, set: { proposed = $0?.setting })) { p in
            NavigationStack { ChoiceSheet(spec: spec(for: p.setting)) }.presentationDetents([.large])
        }
    }

    struct ProposedSetting: Identifiable { let setting: WifiSetting; var id: String { setting.title + setting.displayValue } }

    // MARK: Presets & recommendations

    private func presets(_ t: WifiTuning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(TuningPreset.allCases) { p in
                        Button { preset = p } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: p.symbol).font(.title2).foregroundStyle(Theme.ember).frame(height: 30, alignment: .top)
                                Text(p.title).font(.headline)
                                Text(p.tagline).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                let n = p.plan(from: t, shapingMbps: 100).count
                                Text(n == 0 ? "Already applied" : "\(n) change\(n == 1 ? "" : "s")").font(.caption.weight(.semibold)).foregroundStyle(n == 0 ? Theme.good : Theme.ember)
                            }
                            .padding(14).frame(width: 190, height: 170, alignment: .topLeading).card()
                        }.buttonStyle(.plain).foregroundStyle(.white)
                    }
                }
            }.scrollClipDisabled()
        }
    }

    @ViewBuilder private func recommendations(_ t: WifiTuning) -> some View {
        let recs = Advisor.channelAdvice(tuning: t, airtime5: session.routerStatus?.airtime5, radio5: session.radios.first { $0.band == .ghz5 })
        if !recs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Recommended for gaming")
                VStack(spacing: 0) {
                    ForEach(recs) { r in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: r.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                                .foregroundStyle(r.severity == .warning ? Theme.warn : Theme.info).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.title).font(.subheadline.weight(.semibold))
                                Text(r.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if let s = r.suggestion {
                                    Button("Review: \(s.title) → \(s.displayValue)") {
                                        if case .trafficControl = s { showCake = true } else { proposed = s }
                                    }.font(.footnote.weight(.semibold)).tint(Theme.ember).padding(.top, 2)
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(14)
                        if r.id != recs.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }.card()
            }
        }
    }

    // MARK: Sections

    private func band(_ b: RadioBand, _ t: WifiTuning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(b.label)
            VStack(spacing: 0) {
                row(spec(for: .channel(b, t.channel(b))), value: t.channel(b) == 0 ? "Auto" : "Channel \(t.channel(b))")
                if b == .ghz2 {
                    row(spec(for: .htBandwidth(b, t.ht2)), value: t.ht2.label)
                } else {
                    row(spec(for: .vhtBandwidth(b, b == .ghz5 ? t.vht5 : t.vht5High)), value: (b == .ghz5 ? t.vht5 : t.vht5High).label)
                }
                row(spec(for: .wirelessMode(b, b == .ghz2 ? t.mode2 : b == .ghz5 ? t.mode5 : t.mode5High)), value: (b == .ghz2 ? t.mode2 : b == .ghz5 ? t.mode5 : t.mode5High).label)
                row(spec(for: .txPower(b, b == .ghz2 ? t.tx2 : b == .ghz5 ? t.tx5 : t.tx5High)), value: (b == .ghz2 ? t.tx2 : b == .ghz5 ? t.tx5 : t.tx5High).label)
                row(spec(for: .bandDisabled(b, t.isDisabled(b))), value: t.isDisabled(b) ? "Off" : "On", last: true)
            }.card()
        }
    }

    private func general(_ t: WifiTuning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Radio behaviour")
            VStack(spacing: 0) {
                row(spec(for: .dfs(t.dfsEnabled)), value: t.dfsEnabled ? "On" : "Off")
                row(spec(for: .bandSteeringDisabled(t.bandSteeringDisabled)), value: t.bandSteeringDisabled ? "Disabled" : "Enabled")
                row(spec(for: .outdoorMode(t.outdoorMode)), value: t.outdoorMode ? "On" : "Off")
                row(spec(for: .customPowerTable(t.customPowerTable)), value: t.customPowerTable ? "On" : "Off")
                row(spec(for: .bypassMode(t.bypassMode)), value: t.bypassMode ? "On" : "Off")
                HStack { Text("Country code").font(.body); Spacer(); Text(t.countryCode).foregroundStyle(.secondary); Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary) }
                    .padding(14).accessibilityElement(children: .combine)
            }.card()
        }
    }

    private func network(_ t: WifiTuning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Names & DNS")
            VStack(spacing: 0) {
                row(spec(for: .hiddenSSID(t.networks.first(where: { !$0.isGuest })?.hidden ?? false)), value: (t.networks.first(where: { !$0.isGuest })?.hidden ?? false) ? "Hidden" : "Visible")
                row(spec(for: .secureDNS(t.secureDNS)), value: t.secureDNS ? "On" : "Off")
                row(spec(for: .nameservers(t.nameservers)), value: t.nameservers.isEmpty ? "Automatic" : t.nameservers.joined(separator: ", "), last: true)
            }.card()
        }
    }

    private func trafficControl(_ t: WifiTuning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Bufferbloat · traffic control")
            VStack(alignment: .leading, spacing: 10) {
                Button { showCake = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Smart queue (CAKE)").font(.body.weight(.medium))
                            Text(t.traffic.label).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text("Bufferbloat is the lag you get when something else saturates the link. CAKE shapes traffic slightly below your real speed so the router, not the modem queue, decides what waits.")
                    .font(.footnote).foregroundStyle(.secondary)
                Divider().overlay(.white.opacity(0.08))
                Button { proposed = .dscpMark(t.dscpMark) } label: {
                    HStack { Text("WAN DSCP mark").font(.body.weight(.medium)); Spacer(); Text(t.dscpMark == 0 ? "Off" : "\(t.dscpMark)").foregroundStyle(.secondary); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(14).card()
        }
    }

    private func row(_ s: SettingSpec, value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Button { editing = s } label: {
                HStack(spacing: 10) {
                    Text(s.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(value).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel("\(s.title), \(value)")
            if !last { Divider().overlay(.white.opacity(0.08)).padding(.leading, 14) }
        }
    }

    // MARK: Spec catalogue

    func spec(for s: WifiSetting) -> SettingSpec {
        let t = session.tuning ?? WifiTuning()
        func opt(_ s: WifiSetting, _ label: String, note: String? = nil, rec: Bool = false) -> SettingSpec.Option { .init(setting: s, label: label, note: note, recommended: rec) }
        func onOff(_ make: (Bool) -> WifiSetting, on: String = "On", off: String = "Off", recommendOn: Bool? = nil) -> [SettingSpec.Option] {
            [opt(make(true), on, rec: recommendOn == true), opt(make(false), off, rec: recommendOn == false)]
        }
        switch s {
        case .channel(let b, let cur):
            var list: [SettingSpec.Option] = [opt(.channel(b, 0), "Automatic", note: "The router chooses and may change channel.")]
            if b == .ghz2 {
                list += [1, 6, 11].map { opt(.channel(b, $0), "Channel \($0)", note: "Non-overlapping 2.4 GHz channel.") }
            } else {
                list += Advisor.nonDFS5GHz.map { opt(.channel(b, $0), "Channel \($0)", note: $0 < 100 ? "36–48 block · no radar checks" : "149–161 block · no radar checks", rec: $0 == 149) }
                if t.dfsEnabled || Advisor.isDFS(channel: cur) {
                    list += [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144].map { opt(.channel(b, $0), "Channel \($0)", note: "DFS · can be evicted by radar") }
                }
            }
            return .init(id: s.title, title: s.title, explanation: "Pinning a channel stops the router from hopping mid-game. Pick one with the least interference; non-DFS channels never get evicted by radar.", current: .channel(b, cur), options: list)
        case .htBandwidth(let b, let cur):
            return .init(id: s.title, title: s.title, explanation: "20 MHz is the most robust on a crowded 2.4 GHz band; 40 MHz is faster but overlaps neighbours.", current: .htBandwidth(b, cur),
                         options: HTWidth.allCases.map { opt(.htBandwidth(b, $0), $0.label, rec: $0 == .mhz20 && b == .ghz2) })
        case .vhtBandwidth(let b, let cur):
            return .init(id: s.title, title: s.title, explanation: "Narrower channels are quieter and more reliable; wider ones trade stability for peak speed. 80 MHz is the gaming sweet spot.", current: .vhtBandwidth(b, cur),
                         options: [VHTWidth.default, .disabled, .mhz80, .mhz160].map { opt(.vhtBandwidth(b, $0), $0.label, note: $0 == .mhz160 ? "Needs a clean 160 MHz span; often unstable." : nil, rec: $0 == .mhz80) })
        case .wirelessMode(let b, let cur):
            return .init(id: s.title, title: s.title, explanation: "Which Wi-Fi generations the radio accepts. Leave on automatic unless an old device misbehaves.", current: .wirelessMode(b, cur),
                         options: WirelessModeOption.options(for: b).map { opt(.wirelessMode(b, $0), $0.label) })
        case .txPower(let b, let cur):
            return .init(id: s.title, title: s.title, explanation: "Lower power can reduce interference with neighbours in tight spaces, but shrinks range. Gaming near the router rarely needs less than 100%.", current: .txPower(b, cur),
                         options: TxPower.allCases.map { opt(.txPower(b, $0), $0.label, rec: $0 == .p100) })
        case .dfs(let cur):
            return .init(id: s.title, title: "DFS channels", explanation: "Dynamic Frequency Selection lets Wi-Fi use radar-shared 5 GHz channels. When radar is detected the router must leave instantly, dropping everyone. Off is steadier.", current: .dfs(cur), options: onOff(WifiSetting.dfs, recommendOn: false))
        case .bandSteeringDisabled(let cur):
            return .init(id: s.title, title: "Band steering", explanation: "Band steering nudges devices between 2.4 and 5 GHz. Turn it off if a device keeps hopping bands, or to keep consoles on 5 GHz.", current: .bandSteeringDisabled(cur),
                         options: [opt(.bandSteeringDisabled(false), "Enabled"), opt(.bandSteeringDisabled(true), "Disabled")])
        case .bandDisabled(let b, let cur):
            return .init(id: s.title, title: "\(b.label) radio", explanation: "Switching a radio off removes that band entirely. Devices that only support it will lose Wi-Fi.", current: .bandDisabled(b, cur),
                         options: [opt(.bandDisabled(b, false), "On"), opt(.bandDisabled(b, true), "Off")],
                         danger: "Turning off a band can lock out devices that only support it.")
        case .outdoorMode(let cur):
            return .init(id: s.title, title: s.title, explanation: "Restricts the router to channels and power levels legal outdoors. Only enable it if the router is outside.", current: .outdoorMode(cur), options: onOff(WifiSetting.outdoorMode))
        case .customPowerTable(let cur):
            return .init(id: s.title, title: s.title, explanation: "Uses a factory-calibrated per-channel power table instead of the default.", current: .customPowerTable(cur), options: onOff(WifiSetting.customPowerTable))
        case .bypassMode(let cur):
            return .init(id: s.title, title: "Bypass mode", explanation: "Turns the Starlink router into a plain bridge so another router handles everything. Wi-Fi and DHCP on this router stop working.", current: .bypassMode(cur), options: onOff(WifiSetting.bypassMode),
                         danger: "You will probably lose access to the router and this app until bypass mode is turned off or the router is reset.")
        case .secureDNS(let cur):
            return .init(id: s.title, title: "Secure DNS", explanation: "Encrypts DNS lookups so your ISP can't read or tamper with them.", current: .secureDNS(cur), options: onOff(WifiSetting.secureDNS))
        case .nameservers(let cur):
            return .init(id: s.title, title: "DNS servers", explanation: "Pick which resolver the router hands out. Faster DNS makes pages and game logins snappier.", current: .nameservers(cur),
                         options: [opt(.nameservers([]), "Automatic (Starlink)"), opt(.nameservers(["1.1.1.1", "1.0.0.1"]), "Cloudflare", note: "1.1.1.1"),
                                   opt(.nameservers(["8.8.8.8", "8.8.4.4"]), "Google", note: "8.8.8.8"), opt(.nameservers(["9.9.9.9", "149.112.112.112"]), "Quad9", note: "9.9.9.9")])
        case .hiddenSSID(let cur):
            return .init(id: s.title, title: "Network name", explanation: "Hiding the name doesn't add real security and some consoles struggle to join hidden networks.", current: .hiddenSSID(cur),
                         options: [opt(.hiddenSSID(false), "Visible", rec: true), opt(.hiddenSSID(true), "Hidden")],
                         danger: "Devices may need to re-join the network by typing its name.")
        case .dscpMark(let cur):
            return .init(id: s.title, title: "WAN DSCP mark", explanation: "Tags upstream packets with a priority value. Starlink rarely honours it, so leave this alone unless you know you need it.", current: .dscpMark(cur),
                         options: [0, 8, 16, 26, 34, 46].map { opt(.dscpMark($0), $0 == 0 ? "Off" : "Mark \($0)") })
        case .trafficControl(let cur):
            return .init(id: s.title, title: "Traffic control", explanation: "", current: .trafficControl(cur), options: [])
        }
    }
}

struct WriteModeCard: View {
    @Environment(StarlinkSession.self) private var session
    var body: some View {
        @Bindable var s = session
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: session.writesEnabled ? "pencil.circle.fill" : "lock.shield.fill").font(.title2)
                    .foregroundStyle(session.writesEnabled ? Theme.warn : Theme.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.writesEnabled ? "Writes enabled" : "Read-only mode").font(.headline)
                    Text(session.writesEnabled ? "Changes you confirm will be sent to the router." : "Perigee can look but not touch. Nothing can change on your devices.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable writes", isOn: $s.writesEnabled).labelsHidden().toggleStyle(.switch).tint(Theme.warn)
                    .onChange(of: session.writesEnabled) { _, on in on ? Haptics.warning() : Haptics.select() }
            }
        }
        .padding(16).card(tint: session.writesEnabled ? Theme.warn : Theme.good)
        .accessibilityElement(children: .contain)
    }
}

struct ChangeLogCard: View {
    @Environment(StarlinkSession.self) private var session
    @State private var error: String?
    var body: some View {
        if !session.changeLog.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Changes this session")
                VStack(spacing: 0) {
                    ForEach(session.changeLog) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: r.verified ? "checkmark.seal.fill" : "questionmark.circle.fill").foregroundStyle(r.verified ? Theme.good : Theme.warn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.subheadline.weight(.semibold))
                                Text("\(r.from) → \(r.to)").font(.footnote).foregroundStyle(.secondary)
                                Text(Fmt.relative(r.date) + (r.revertedAt != nil ? " · reverted" : "")).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if r.revertedAt == nil && r.canRevert {
                                Button("Revert") { Task { do { _ = try await session.revert(r); Haptics.success() } catch { self.error = error.localizedDescription } } }
                                    .buttonStyle(.bordered).controlSize(.small).tint(Theme.ember).disabled(!session.writesEnabled)
                            }
                        }.padding(14)
                        if r.id != session.changeLog.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }.card()
                if let error { Text(error).font(.caption).foregroundStyle(Theme.bad) }
            }
        }
    }
}
