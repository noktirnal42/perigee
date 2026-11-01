import SwiftUI
import StarlinkKit

/// Shared confirmation block: current vs new, plain-language impact, then confirm (slide for risky changes).
struct ChangeConfirmation: View {
    @Environment(StarlinkSession.self) private var session
    let current: WifiSetting
    let proposed: WifiSetting
    var danger: String? = nil
    let onApplied: (ChangeRecord) -> Void
    @State private var state: Phase = .idle
    enum Phase: Equatable { case idle, applying, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                valueBox("Now", current.displayValue, tint: .white)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                valueBox("New", proposed.displayValue, tint: Theme.ember)
            }
            if let w = proposed.impact.warning {
                Label(w, systemImage: "bolt.horizontal.circle.fill").font(.footnote).foregroundStyle(Theme.warn)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            if let d = danger {
                Label(d, systemImage: "exclamationmark.octagon.fill").font(.footnote).foregroundStyle(Theme.bad)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.bad.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Perigee sends only this one field, then re-reads the router to confirm it took. You can revert in one tap.")
                .font(.caption).foregroundStyle(.secondary)

            if !session.writesEnabled {
                Label("Turn on “Enable writes” in the Tune tab first.", systemImage: "lock.fill").font(.subheadline).foregroundStyle(.secondary)
            } else if state == .applying {
                HStack { ProgressView(); Text("Applying — the router may restart Wi-Fi…").font(.subheadline) }
            } else if proposed.risk == .high {
                SlideToConfirm(label: "Slide to apply", tint: Theme.bad) { await apply() }
            } else {
                Button { Task { await apply() } } label: { Text("Apply change").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.borderedProminent).tint(Theme.ember).disabled(current == proposed)
            }
            if case .failed(let msg) = state { Text(msg).font(.footnote).foregroundStyle(Theme.bad) }
        }
    }

    private func valueBox(_ t: String, _ v: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).eyebrow()
            Text(v).font(.headline).foregroundStyle(tint).lineLimit(2).minimumScaleFactor(0.7)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func apply() async {
        state = .applying
        do { let rec = try await session.apply(proposed, expected: current); Haptics.success(); state = .idle; onApplied(rec) }
        catch { Haptics.warning(); state = .failed(error.localizedDescription) }
    }
}

struct ChoiceSheet: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let spec: SettingSpec
    @State private var picked: SettingSpec.Option.ID?
    @State private var result: ChangeRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text(spec.explanation).font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(spec.options) { o in
                        Button { Haptics.select(); picked = o.id; result = nil } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(o.label).font(.body.weight(.medium))
                                        if o.recommended { Text("Recommended").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.good.opacity(0.25), in: Capsule()) }
                                    }
                                    if let n = o.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if isCurrent(o) { Text("Current").font(.caption).foregroundStyle(.secondary) }
                                Image(systemName: (picked ?? currentID) == o.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle((picked ?? currentID) == o.id ? Theme.ember : .secondary)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if o.id != spec.options.last?.id { Divider().overlay(.white.opacity(0.08)).padding(.leading, 14) }
                    }
                }.card()

                if let result {
                    ResultCard(record: result)
                } else if let o = spec.options.first(where: { $0.id == (picked ?? currentID) }), !isCurrent(o) {
                    ChangeConfirmation(current: spec.current, proposed: o.setting, danger: spec.danger) { result = $0 }
                        .padding(16).card()
                }
            }.padding(16).frame(maxWidth: 700)
        }
        .background(ScreenBackground())
        .navigationTitle(spec.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func isCurrent(_ o: SettingSpec.Option) -> Bool { o.setting == spec.current }
    private var currentID: SettingSpec.Option.ID? { spec.options.first(where: isCurrent)?.id }
}

struct ResultCard: View {
    @Environment(StarlinkSession.self) private var session
    let record: ChangeRecord
    @State private var reverted = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(record.verified ? "Applied and verified" : "Sent, but not confirmed yet", systemImage: record.verified ? "checkmark.seal.fill" : "questionmark.circle.fill")
                .font(.headline).foregroundStyle(record.verified ? Theme.good : Theme.warn)
            Text("\(record.title): \(record.from) → \(record.to)").font(.subheadline)
            if !record.verified { Text("The router didn't confirm the new value within a minute. It may still be restarting Wi-Fi. Pull to refresh in Tune.").font(.footnote).foregroundStyle(.secondary) }
            if reverted { Label("Reverted", systemImage: "arrow.uturn.backward").foregroundStyle(.secondary) }
            else if !record.canRevert {
                Label("The previous value can't be written back exactly, so there's no one-tap revert. Choose a new value to change it.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button { Task { do { _ = try await session.revert(record); reverted = true; Haptics.success() } catch { self.error = error.localizedDescription } } } label: {
                    Label("Revert to \(record.from)", systemImage: "arrow.uturn.backward")
                }.buttonStyle(.bordered).tint(Theme.ember)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.bad) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.good)
    }
}

// MARK: CAKE

struct CakeSheet: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var mbps: Double = 100
    @State private var priority: CakeParams.Priority = .diffserv4
    @State private var ack: CakeParams.AckFilter = .on
    @State private var off = false
    @State private var result: ChangeRecord?

    private var proposed: WifiSetting {
        off ? .trafficControl(.none) : .trafficControl(.cake(CakeParams(bandwidth: mbps.rounded(), priority: priority, ackFilter: ack)))
    }
    private var current: WifiSetting { .trafficControl(session.tuning?.traffic ?? .unset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("CAKE is a smart queue. Set the rate to about 90% of your measured download speed and heavy downloads can no longer stuff the buffers that cause lag spikes in cloud gaming.")
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Smart queue", isOn: Binding(get: { !off }, set: { off = !$0 })).tint(Theme.ember)
                    if !off {
                        HStack(alignment: .firstTextBaseline) { Text("Shaping rate").font(.body.weight(.medium)); Spacer(); Text("\(Int(mbps)) Mbps").font(.numeral(22)) }
                        Slider(value: $mbps, in: 10...500, step: 5).tint(Theme.ember)
                        Text("Run a speed test, multiply by 0.9, and enter it here. Too high and bufferbloat returns; too low and you waste speed. The router's schema doesn't state units; Perigee assumes Mbit/s (its own ACK-queue values look like it), so re-test with the stall tester after applying. Revert is one tap.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Picker("Priority tiers", selection: $priority) { ForEach(CakeParams.Priority.allCases) { Text($0.label).tag($0) } }
                        Text("Diffserv 4 puts interactive traffic (games, calls) ahead of bulk downloads.").font(.footnote).foregroundStyle(.secondary)
                        Picker("ACK filter", selection: $ack) { ForEach(CakeParams.AckFilter.allCases) { Text($0.label).tag($0) } }
                        Text("Thins out redundant TCP acknowledgements on slow uplinks. Helps asymmetric connections.").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(16).card()

                if let result { ResultCard(record: result) }
                else {
                    ChangeConfirmation(current: current, proposed: proposed) { result = $0 }.padding(16).card()
                }
            }.padding(16).frame(maxWidth: 700)
        }
        .background(ScreenBackground())
        .navigationTitle("Smart queue (CAKE)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            if case .cake(let c) = session.tuning?.traffic { mbps = c.bandwidth; priority = c.priority; ack = c.ackFilter }
        }
        .onChange(of: proposed) { _, _ in result = nil }
    }
}

// MARK: Presets

struct PresetSheet: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let preset: TuningPreset
    @State private var shaping: Double = 100
    @State private var useShaping = true
    @State private var progress: [String] = []
    @State private var running = false
    @State private var error: String?
    @State private var done: [ChangeRecord] = []

    private var plan: [WifiSetting] { preset.plan(from: session.tuning ?? WifiTuning(), shapingMbps: useShaping ? shaping.rounded() : nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Label(preset.title, systemImage: preset.symbol).font(.wide(24, weight: .bold))
                Text(preset.tagline).foregroundStyle(.secondary)

                if preset != .maxThroughput {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Also set up bufferbloat control (CAKE)", isOn: $useShaping).tint(Theme.ember)
                        if useShaping {
                            HStack { Text("Rate"); Spacer(); Text("\(Int(shaping)) Mbps").font(.numeral(20)) }
                            Slider(value: $shaping, in: 10...500, step: 5).tint(Theme.ember)
                            Text("About 90% of your real download speed.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(16).card()
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("WHAT WILL CHANGE").eyebrow().padding(14)
                    if plan.isEmpty { Text("Nothing. This preset is already in place.").padding(14).foregroundStyle(.secondary) }
                    ForEach(plan.indices, id: \.self) { i in
                        let s = plan[i]
                        let cur = s.current(in: session)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) { Text(s.title).font(.subheadline.weight(.semibold)); Text("\(cur) → \(s.displayValue)").font(.footnote).foregroundStyle(.secondary) }
                            Spacer()
                            if i < done.count { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good) }
                        }.padding(14)
                        Divider().overlay(.white.opacity(0.08))
                    }
                }.card()

                if plan.contains(where: { $0.impact == .wifiRestart }) {
                    Label(ChangeImpact.wifiRestart.warning ?? "", systemImage: "bolt.horizontal.circle.fill").font(.footnote).foregroundStyle(Theme.warn)
                        .padding(12).background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("Each step is a separate, verified, single-field write. If one fails the rest are skipped and you can revert the finished ones.")
                    .font(.caption).foregroundStyle(.secondary)

                if !session.writesEnabled { Label("Turn on “Enable writes” in the Tune tab first.", systemImage: "lock.fill").foregroundStyle(.secondary) }
                else if running { HStack { ProgressView(); Text("Applying \(done.count + 1) of \(plan.count)…") } }
                else if !plan.isEmpty && done.count < plan.count {
                    SlideToConfirm(label: "Slide to apply \(plan.count) change\(plan.count == 1 ? "" : "s")", tint: Theme.ember) { await run() }
                }
                if !done.isEmpty && !running {
                    Button { Task { await revertAll() } } label: { Label("Revert these changes", systemImage: "arrow.uturn.backward") }.buttonStyle(.bordered).tint(Theme.ember)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
            }.padding(16).frame(maxWidth: 700)
        }
        .background(ScreenBackground())
        .navigationTitle(preset.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { if case .cake(let c) = session.tuning?.traffic { shaping = c.bandwidth } }
    }

    private func run() async {
        running = true; error = nil; done = []
        let steps = plan
        for s in steps {
            do { done.append(try await session.apply(s)) }
            catch { self.error = "Stopped at “\(s.title)”: \(error.localizedDescription)"; break }
        }
        running = false
    }

    private func revertAll() async {
        running = true
        for r in done.reversed() { _ = try? await session.revert(r) }
        done = []; running = false
    }
}

private extension WifiSetting {
    @MainActor func current(in session: StarlinkSession) -> String {
        guard let t = session.tuning else { return "—" }
        switch self {
        case .dfs: return t.dfsEnabled ? "On" : "Off"
        case .vhtBandwidth(.ghz5, _): return t.vht5.label
        case .wirelessMode(.ghz5, _): return t.mode5.label
        case .txPower(.ghz5, _): return t.tx5.label
        case .channel(.ghz5, _): return t.channel5 == 0 ? "Auto" : "Channel \(t.channel5)"
        case .trafficControl: return t.traffic.label
        default: return "—"
        }
    }
}
