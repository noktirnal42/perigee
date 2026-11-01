import SwiftUI
import StarlinkKit

@main
struct PerigeeApp: App {
    @State private var session = PerigeeApp.makeSession()

    /// `-demo` launches against the built-in sample network (used for screenshots and previews).
    private static func makeSession() -> StarlinkSession {
        StarlinkSession(source: CommandLine.arguments.contains("-demo") ? .demo : .live,
                        demoRefusesWrites: CommandLine.arguments.contains("-refuse-writes"))
    }

    var body: some Scene {
        #if os(macOS)
        Window("Perigee", id: "main") {
            RootView().environment(session).frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1100, height: 760)
        .commands { PerigeeCommands(session: session) }

        MenuBarExtra {
            MenuBarStatus().environment(session)
        } label: {
            Label(menuTitle, systemImage: "antenna.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(session).frame(width: 520, height: 640).preferredColorScheme(.dark) }
        #else
        WindowGroup { RootView().environment(session) }
        #endif
    }

    #if os(macOS)
    private var menuTitle: String {
        guard let p = session.routerStatus?.internetPingMs else { return "—" }
        return "\(Fmt.ms(p)) ms"
    }
    #endif
}

#if os(macOS)
struct PerigeeCommands: Commands {
    let session: StarlinkSession
    var body: some Commands {
        CommandMenu("Connection") {
            Button("Refresh Now") { Task { await session.refreshNow() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Reconnect") { session.reconnect() }
            Divider()
            Button(session.writesEnabled ? "Disable Writes" : "Enable Writes…") { session.writesEnabled.toggle() }.keyboardShortcut("w", modifiers: [.command, .option])
            Button(session.source == .demo ? "Use Live Devices" : "Use Demo Data") { session.setSource(session.source == .demo ? .live : .demo) }
        }
    }
}
#endif
