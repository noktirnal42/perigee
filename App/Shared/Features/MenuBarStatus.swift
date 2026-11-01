#if os(macOS)
import SwiftUI
import StarlinkKit

/// Live ping & jitter in the menu bar.
struct MenuBarStatus: View {
    @Environment(StarlinkSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perigee").font(.headline)
            Divider()
            row("Status", { switch session.link { case .online: "Online"; case .degraded(let s): s; case .offline: "Offline"; case .connecting: "Connecting…" } }())
            row("Latency", "\(Fmt.ms(session.routerStatus?.internetPingMs)) ms")
            row("Jitter", "\(Fmt.ms(session.jitter)) ms")
            row("Ping success", "\(Fmt.percent(session.pingSuccess))%")
            row("Devices", "\(session.wirelessClients.count)")
            Divider()
            Button("Open Perigee") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.padding(12).frame(width: 240)
    }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() } }
}
#endif
