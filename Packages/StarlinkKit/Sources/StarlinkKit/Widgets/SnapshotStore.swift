import Foundation

/// Reads/writes `StatusSnapshot` to the app's shared App Group container, so the widget extension and
/// headless App Intents — separate processes with no gRPC connection of their own — can show "what's going
/// on" without ever reaching the network themselves. Plain JSON, same hygiene as every other store here.
public enum SnapshotStore {
    public static let appGroupID = "group.dev.noktirnal.perigee"
    private static let filename = "status-snapshot.json"

    /// `directory` is for tests only; the app and widget both call this with no argument, which resolves to
    /// the shared App Group container (`nil` when that container isn't available, e.g. no entitlement).
    public static func write(_ snapshot: StatusSnapshot, directory: URL? = nil) {
        guard let url = fileURL(directory: directory), let data = try? JSONEncoder.iso.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(directory: URL? = nil) -> StatusSnapshot? {
        guard let url = fileURL(directory: directory), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode(StatusSnapshot.self, from: data)
    }

    private static func fileURL(directory: URL?) -> URL? {
        let dir = directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        return dir?.appendingPathComponent(filename)
    }
}
