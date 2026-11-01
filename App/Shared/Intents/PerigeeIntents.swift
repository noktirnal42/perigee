import AppIntents
import Foundation
import StarlinkKit

extension Notification.Name {
    static let perigeeOpenDiagnostics = Notification.Name("dev.noktirnal.perigee.openDiagnostics")
    static let perigeeOpenTune = Notification.Name("dev.noktirnal.perigee.openTune")
}

/// Headless: answers from the last snapshot the app wrote, no need to open the app or touch the network.
struct IsStarlinkOnlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Is Starlink Online?"
    static let description = IntentDescription("Checks Perigee's last known status without opening the app.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read() else {
            return .result(dialog: "Perigee hasn't connected yet. Open the app once to get started.")
        }
        let age = Date().timeIntervalSince(snapshot.updatedAt)
        let freshness = age < 120 ? "" : " (as of \(Int(age / 60)) minutes ago)"
        switch snapshot.status {
        case .online:
            let ping = snapshot.internetPingMs.map { ", ping \(Int($0)) milliseconds" } ?? ""
            return .result(dialog: "Starlink is online\(ping)\(freshness).")
        case .degraded:
            return .result(dialog: "Starlink is degraded: \(snapshot.statusText)\(freshness).")
        case .offline:
            return .result(dialog: "Starlink is offline\(freshness).")
        case .connecting:
            return .result(dialog: "Perigee is still connecting\(freshness).")
        }
    }
}

/// Opens the app to the stall tester rather than running one headlessly — consistent with Perigee's safety
/// model, where every test run and every setting change is something you start yourself, never Siri for you.
struct OpenStallTestIntent: AppIntent {
    static let title: LocalizedStringResource = "Run a Stall Test"
    static let description = IntentDescription("Opens Perigee to the stall tester.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .perigeeOpenDiagnostics, object: nil)
        return .result()
    }
}

/// Opens the app to Wi-Fi tuning — never applies a change itself; you still confirm every write in the app.
struct OpenTuneIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Wi-Fi Tuning"
    static let description = IntentDescription("Opens Perigee to the Tune screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .perigeeOpenTune, object: nil)
        return .result()
    }
}

struct PerigeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IsStarlinkOnlineIntent(),
            phrases: ["Is \(.applicationName) online?", "Check \(.applicationName) status"],
            shortTitle: "Check Status", systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: OpenStallTestIntent(),
            phrases: ["Run a stall test with \(.applicationName)", "Test my connection with \(.applicationName)"],
            shortTitle: "Run Stall Test", systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenTuneIntent(),
            phrases: ["Open \(.applicationName) tuning"],
            shortTitle: "Open Tuning", systemImageName: "slider.horizontal.3"
        )
    }
}
