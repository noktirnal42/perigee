import SwiftUI
import StarlinkKit

struct SettingsView: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var routerHost = ""
    @State private var dishHost = ""
    @State private var error: String?
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
                section("Devices") {
                    field("Router address", text: $routerHost, hint: "192.168.1.1 · port 9000")
                    field("Dish address", text: $dishHost, hint: "192.168.100.1 · port 9200")
                    Button("Save & reconnect") { session.routerHost = routerHost; session.dishHost = dishHost; session.reconnect() }
                        .buttonStyle(.bordered).tint(Theme.ember)
                    Text("Only works while this device is on your Starlink network. If connections fail on iOS, allow Local Network access for Perigee in Settings › Privacy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                section("Safety") {
                    ExplainedToggle(title: "Enable writes", explanation: "Off by default every launch. While off, Perigee cannot change anything on your router or dish.", isOn: $s.writesEnabled)
                    Text("Authentication, signing, debug, factory-reset and test-mode methods are blocked in code and can never be sent, even with writes on. Wi-Fi passwords are hidden until you authenticate and are never logged.")
                        .font(.footnote).foregroundStyle(.secondary)
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
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { SectionTitle(title); VStack(alignment: .leading, spacing: 12, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).card() }
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
