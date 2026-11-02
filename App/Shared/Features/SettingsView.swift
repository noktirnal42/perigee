import SwiftUI
import StarlinkKit

struct SettingsView: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var routerHost = ""
    @State private var dishHost = ""
    @State private var error: String?
    @State private var rules: [AlertRule] = []
    @State private var siteSheet: SiteSheetTarget?
    static let repoURL = URL(string: "https://github.com/noktirnal42/perigee")!

    var body: some View {
        @Bindable var s = session
        ScrollView {
            VStack(spacing: Theme.spacing) {
                section("Data source") {
                    PillPicker(options: [(DataSource.live, "Live devices"), (DataSource.demo, "Demo data")], selection: Binding(get: { session.source }, set: { session.setSource($0) }))
                    Text(session.source == .live ? "Talking to your router and dish over the local network." : "Showing a built-in sample network. Nothing is sent anywhere. Great for exploring.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                section("Sites") {
                    Text("Switch between saved Starlink installations — home, a second property, an RV or boat dish. Each keeps its own history, alerts and saved tests.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(session.siteStore.sites) { site in
                            siteRow(site)
                            if site.id != session.siteStore.sites.last?.id { Divider().overlay(.white.opacity(0.08)) }
                        }
                    }
                    Button { siteSheet = .add } label: { Label("Add site", systemImage: "plus.circle") }
                        .buttonStyle(.bordered).tint(.white)
                }
                section("Devices") {
                    field("Router address", text: $routerHost, hint: "192.168.1.1 · port 9000")
                    field("Dish address", text: $dishHost, hint: "192.168.100.1 · port 9200")
                    Button("Save & reconnect") {
                        session.routerHost = routerHost; session.dishHost = dishHost
                        var site = session.currentSite; site.routerHost = routerHost; site.dishHost = dishHost
                        session.siteStore.update(site); session.refreshCurrentSiteFromStore()
                        session.reconnect()
                    }
                    .buttonStyle(.bordered).tint(Theme.ember)
                    Text("Only works while this device is on your Starlink network. If connections fail on iOS, allow Local Network access for Perigee in Settings › Privacy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                section("Safety") {
                    ExplainedToggle(title: "Enable writes", explanation: "Off by default every launch. While off, Perigee cannot change anything on your router or dish.", isOn: $s.writesEnabled)
                    Text("Authentication, signing, debug, factory-reset and test-mode methods are blocked in code and can never be sent, even with writes on. Wi-Fi passwords are hidden until you authenticate and are never logged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                section("Alerts") {
                    Text("Local notifications only, from this device's own history. Nothing is sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach($rules) { $rule in
                        alertRuleRow($rule)
                        if rule.id != rules.last?.id { Divider().overlay(.white.opacity(0.08)) }
                    }
                }
                if session.writesEnabled {
                    section("Router") {
                        Text("Restarting the router drops every device for about two minutes.").font(.footnote).foregroundStyle(.secondary)
                        SlideToConfirm(label: "Slide to reboot router", tint: Theme.bad) {
                            do { try await session.rebootRouter() } catch { self.error = error.localizedDescription }
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
                    }
                }
                section("About") {
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(.secondary) }
                    Link(destination: Self.repoURL) { Label("Source & docs on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Text("Perigee is an unofficial, independent companion app. It is not made, endorsed or supported by SpaceX or Starlink. “Starlink” is a trademark of its owner and is used only to describe compatibility.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: 640)
        }
        .background(ScreenBackground())
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { routerHost = session.routerHost; dishHost = session.dishHost }
        .task { rules = await session.automation.rules }
        .onChange(of: session.currentSite) { _, site in routerHost = site.routerHost; dishHost = site.dishHost }
        .sheet(item: $siteSheet) { target in
            switch target {
            case .add: SiteEditSheet(editing: nil)
            case .edit(let site): SiteEditSheet(editing: site)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { SectionTitle(title); VStack(alignment: .leading, spacing: 12, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).card() }
    }

    private func siteRow(_ site: Site) -> some View {
        let isCurrent = site.id == session.currentSite.id
        return HStack(spacing: 10) {
            Button {
                if !isCurrent { session.switchSite(to: site.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isCurrent ? Theme.ember : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name).font(.body.weight(.medium)).foregroundStyle(.white)
                        Text("\(site.routerHost) · \(site.dishHost)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { siteSheet = .edit(site) } label: { Image(systemName: "pencil.circle") }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }

    private func alertRuleRow(_ rule: Binding<AlertRule>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { rule.wrappedValue.enabled }, set: { on in
                rule.wrappedValue.enabled = on
                Task { await session.automation.setRules(rules) }
            })) {
                Text(rule.wrappedValue.title).font(.body.weight(.medium))
            }.toggleStyle(.switch).tint(Theme.ember)
            if !rule.wrappedValue.metric.isReachability {
                Text("Triggers after \(Int(rule.wrappedValue.sustainedFor))s sustained \(rule.wrappedValue.condition.symbol) \(rule.wrappedValue.metric.isFraction ? "\(Int(rule.wrappedValue.threshold * 100))%" : "\(Int(rule.wrappedValue.threshold)) \(rule.wrappedValue.metric.unit)").")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Triggers after \(Int(rule.wrappedValue.sustainedFor))s not answering.").font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                #endif
        }
    }
}
