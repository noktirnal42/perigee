import SwiftUI
import Charts
import StarlinkKit

struct DishContent: View {
    @Environment(StarlinkSession.self) private var session
    @State private var pending: DishSetting?
    @State private var error: String?
    @State private var stowedAlert = false

    var body: some View {
        VStack(spacing: Theme.spacing) {
            hero
            tiles
            obstruction
            history
            settings
            software
            if session.isDenied("get_status") == false { stow }
            ChangeLogCard()
        }
        .confirmationDialog(pending.map { "Change \($0.title) to \($0.displayValue)?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Apply to dish") { if let p = pending { Task { await apply(p) } } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("Perigee sends only this field and then re-reads the dish to verify. You can revert from the change log.") }
    }

    private var hero: some View {
        let s = session.dishStatus
        return HStack(spacing: 16) {
            Image("DishRender").resizable().scaledToFit().frame(width: 150, height: 125).shadow(color: .black.opacity(0.5), radius: 10, y: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your dish").font(.wide(22, weight: .bold))
                StatusChip(text: s.map { $0.disablementCode == "OKAY" ? "Healthy" : $0.disablementCode.capitalized } ?? "Connecting",
                           color: (s?.hardwareHealthy ?? true) ? Theme.good : Theme.warn, pulse: true)
                if let s {
                    Text("\(s.identity.hardwareVersion) · \(s.identity.softwareVersion)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("Up \(Fmt.uptime(s.identity.uptime))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }.padding(16).card()
    }

    private var tiles: some View {
        let s = session.dishStatus
        let cols = [GridItem(.adaptive(minimum: 165, maximum: 300), spacing: 12)]
        let down = Fmt.rate(s?.downlinkBps ?? 0), up = Fmt.rate(s?.uplinkBps ?? 0)
        let h = session.dishHistory
        return LazyVGrid(columns: cols, spacing: 12) {
            StatTile(title: "Latency", value: Fmt.ms(s?.popPingMs), unit: "ms", caption: "to the network edge",
                     series: Fmt.downsample(Array((h?.latencyMs ?? []).suffix(900)), to: 60))
            StatTile(title: "Packet loss", value: Fmt.percent(s?.popPingDropRate ?? Advisor.successRate(dropRate: h?.dropRate ?? []).map { 1 - $0 }), unit: "%",
                     caption: "last 15 minutes", tint: Theme.warn)
            StatTile(title: "Download", value: down.0, unit: down.1, caption: "right now",
                     series: Fmt.downsample((h?.downlinkBps ?? []).map { Optional($0 / 1e6) }, to: 60), tint: Theme.info)
            StatTile(title: "Upload", value: up.0, unit: up.1, caption: "right now", series: Fmt.downsample((h?.uplinkBps ?? []).map { Optional($0 / 1e6) }, to: 60), tint: Theme.dust)
            StatTile(title: "Tilt", value: s?.tiltDeg.map { String(format: "%.1f", $0) } ?? "—", unit: "°", caption: "from vertical")
            StatTile(title: "Pointing", value: s?.elevationDeg.map { String(format: "%.0f", $0) } ?? "—", unit: "° el",
                     caption: "azimuth \(s?.azimuthDeg.map { String(format: "%.0f°", $0) } ?? "—")")
        }
    }

    private var obstruction: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Obstruction map")
            VStack(spacing: 10) {
                if let m = session.obstruction { ObstructionMapView(map: m).frame(height: 300) }
                else { ProgressView().frame(height: 200) }
                HStack(spacing: 14) {
                    legend(Theme.good, "Clear"); legend(Theme.bad, "Blocked"); legend(.white.opacity(0.15), "Not seen yet")
                }.font(.caption)
                Text("The map is drawn relative to the dish itself (not compass north). Red wedges show where trees, roofs or poles block its view of the satellites.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(16).frame(maxWidth: .infinity).card()
        }
    }
    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 5) { Circle().fill(c).frame(width: 9, height: 9); Text(t) } }

    @ViewBuilder private var history: some View {
        if let h = session.dishHistory, !h.latencyMs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Last 15 minutes")
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LATENCY (MS)").eyebrow()
                        Chart(Array(Fmt.downsample(h.latencyMs, to: 180).enumerated()), id: \.offset) { i, v in
                            AreaMark(x: .value("t", i), y: .value("ms", v)).foregroundStyle(LinearGradient(colors: [Theme.signal.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("t", i), y: .value("ms", v)).foregroundStyle(Theme.signal)
                        }.chartXAxis(.hidden).frame(height: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THROUGHPUT (MBPS)").eyebrow()
                        Chart {
                            ForEach(Array(Fmt.downsample(h.downlinkBps.map { Optional($0 / 1e6) }, to: 180).enumerated()), id: \.offset) { i, v in
                                LineMark(x: .value("t", i), y: .value("Mbps", v), series: .value("d", "Down")).foregroundStyle(Theme.info)
                            }
                            ForEach(Array(Fmt.downsample(h.uplinkBps.map { Optional($0 / 1e6) }, to: 180).enumerated()), id: \.offset) { i, v in
                                LineMark(x: .value("t", i), y: .value("Mbps", v), series: .value("d", "Up")).foregroundStyle(Theme.dust)
                            }
                        }.chartXAxis(.hidden).frame(height: 120)
                    }
                    if !h.outages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECENT OUTAGES").eyebrow()
                            ForEach(h.outages.suffix(5).reversed()) { o in
                                HStack { Text(o.reason.capitalized).font(.subheadline); Spacer(); Text("\(Int(o.duration)) s").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }.padding(16).card()
            }
        }
    }

    @ViewBuilder private var settings: some View {
        if let c = session.dishSettings {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Dish settings")
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        pickerRow("Snow melt", "Heats the dish to clear snow. Uses extra power while active.", selection: c.snowMelt, options: SnowMeltMode.allCases, label: \.label) { pending = .snowMelt($0) }
                        Divider().overlay(.white.opacity(0.08))
                        VStack(alignment: .leading, spacing: 6) {
                            ExplainedToggle(title: "Sleep schedule", explanation: "Powers the dish down each day for the window below, saving energy while you sleep.", isOn: Binding(get: { c.powerSave }, set: { pending = .powerSave($0) }), disabled: !session.writesEnabled)
                            if c.powerSave || c.powerSaveDurationMinutes > 0 {
                                Text("Sleeps at \(Self.hhmm(c.powerSaveStartMinutes)) UTC for \(c.powerSaveDurationMinutes / 60) h \(c.powerSaveDurationMinutes % 60) min").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(14)
                        Divider().overlay(.white.opacity(0.08))
                        ExplainedToggle(title: "Defer software updates", explanation: "Waits up to three days before installing a new version, so an update doesn't land mid-game.", isOn: Binding(get: { c.threeDayDeferral }, set: { pending = .threeDayDeferral($0) }), disabled: !session.writesEnabled).padding(14)
                        Divider().overlay(.white.opacity(0.08))
                        VStack(alignment: .leading, spacing: 6) {
                            Stepper("Update restart hour: \(c.updateRebootHour):00", value: Binding(get: { c.updateRebootHour }, set: { pending = .updateRebootHour($0) }), in: 0...23).disabled(!session.writesEnabled)
                            Text("When the dish may restart to finish an update. Pick a time you're never playing.").font(.footnote).foregroundStyle(.secondary)
                        }.padding(14)
                        Divider().overlay(.white.opacity(0.08))
                        pickerRow("Dish levelling", "Force level keeps the dish flat instead of tilting toward the satellites.", selection: c.levelDish, options: DishLevelMode.allCases, label: \.label) { pending = .levelDish($0) }
                    }
                }.card()
                if !session.writesEnabled { Label("Turn on “Enable writes” in Tune to change dish settings.", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
            }
        }
    }

    private func pickerRow<T: Hashable & Identifiable>(_ title: String, _ note: String, selection: T, options: [T], label: KeyPath<T, String>, set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer()
                Picker(title, selection: Binding(get: { selection }, set: { if $0 != selection { set($0) } })) {
                    ForEach(options) { Text($0[keyPath: label]).tag($0) }
                }.labelsHidden().disabled(!session.writesEnabled)
            }
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }.padding(14)
    }

    private var software: some View {
        let s = session.dishStatus
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Software")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { Text("Version").foregroundStyle(.secondary); Text(s?.identity.softwareVersion ?? "—").font(.body.monospacedDigit()).gridColumnAlignment(.trailing) }
                GridRow { Text("Update state").foregroundStyle(.secondary); Text((s?.softwareUpdateState ?? "—").replacingOccurrences(of: "_", with: " ").capitalized) }
                GridRow { Text("Ethernet").foregroundStyle(.secondary); Text("\(s?.ethSpeedMbps ?? 0) Mbps") }
                GridRow { Text("Class of service").foregroundStyle(.secondary); Text((s?.classOfService ?? "—").capitalized) }
                GridRow { Text("Mobility").foregroundStyle(.secondary); Text((s?.mobility ?? "—").capitalized) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private var stow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Stow dish")
            VStack(alignment: .leading, spacing: 12) {
                Text("Stowing points the dish flat for transport or storm protection. Internet stops until you unstow it.").font(.footnote).foregroundStyle(.secondary)
                if session.writesEnabled {
                    SlideToConfirm(label: "Slide to stow dish", tint: Theme.bad) { await stowDish(true) }
                    SlideToConfirm(label: "Slide to unstow", tint: Theme.good) { await stowDish(false) }
                } else { Label("Enable writes in Tune to use this.", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary) }
            }.padding(16).card()
        }
    }

    private func apply(_ s: DishSetting) async {
        error = nil
        do { _ = try await session.apply(s); Haptics.success() } catch { self.error = error.localizedDescription; Haptics.warning() }
        pending = nil
    }
    private func stowDish(_ stowed: Bool) async {
        do { try await session.setDishStowed(stowed) } catch { self.error = error.localizedDescription }
    }
    static func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60 % 24, m % 60) }
}

/// Polar sky view. The device sends a square grid; cells outside the inscribed circle are ignored.
struct ObstructionMapView: View {
    let map: ObstructionMap
    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let cell = side / CGFloat(map.cols)
            let center = CGPoint(x: origin.x + side / 2, y: origin.y + side / 2)
            var clip = ctx
            clip.clip(to: Path(ellipseIn: CGRect(x: origin.x, y: origin.y, width: side, height: side)))
            clip.fill(Path(CGRect(origin: origin, size: CGSize(width: side, height: side))), with: .color(.white.opacity(0.05)))
            for r in 0..<map.rows { for c in 0..<map.cols {
                let v = map.value(row: r, col: c)
                guard v >= 0 else { continue }
                let color: Color = v < 0.05 ? Theme.bad.opacity(0.9) : Theme.good.opacity(0.35 + 0.55 * Double(min(1, v)))
                clip.fill(Path(CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell + 0.4, height: cell + 0.4)), with: .color(color))
            } }
            for f in [0.33, 0.66, 1.0] {
                let r = side / 2 * f
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.25)), lineWidth: 0.8)
            }
            var cross = Path(); cross.move(to: CGPoint(x: center.x, y: origin.y)); cross.addLine(to: CGPoint(x: center.x, y: origin.y + side))
            cross.move(to: CGPoint(x: origin.x, y: center.y)); cross.addLine(to: CGPoint(x: origin.x + side, y: center.y))
            ctx.stroke(cross, with: .color(.white.opacity(0.15)), lineWidth: 0.6)
            for (t, p) in [("N", CGPoint(x: center.x, y: origin.y - 2)), ("S", CGPoint(x: center.x, y: origin.y + side + 2)),
                           ("E", CGPoint(x: origin.x + side + 8, y: center.y)), ("W", CGPoint(x: origin.x - 8, y: center.y))] {
                ctx.draw(Text(t).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7)), at: p)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Obstruction map. \(Int(Double(map.snr.filter { $0 >= 0 && $0 < 0.05 }.count) / Double(max(1, map.snr.filter { $0 >= 0 }.count)) * 100)) percent of observed sky is blocked.")
    }
}
