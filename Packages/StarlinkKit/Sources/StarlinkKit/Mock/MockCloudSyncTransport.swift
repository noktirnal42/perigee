import Foundation

/// In-memory stand-in for CloudKit: same shape as the real container but all state lives in an array, nothing
/// persisted, no network. Backs `SyncEngine`'s tests and demo mode, the same role `MockRouter` plays for writes.
public actor MockCloudSyncTransport: CloudSyncTransport {
    private struct Entry { var key: String; var record: SyncRecord?; var deleted: Bool }
    private var log: [Entry] = []

    /// Flip to `false` to simulate "not signed into iCloud" in tests.
    public var available = true

    public init() {}

    public func accountAvailable() async -> Bool { available }

    public func push(upserts: [SyncRecord], deletions: [(kind: SyncKind, id: String)]) async throws {
        guard available else { throw SyncError.accountUnavailable }
        for r in upserts { log.append(Entry(key: "\(r.kind.rawValue)/\(r.id)", record: r, deleted: false)) }
        for d in deletions { log.append(Entry(key: "\(d.kind.rawValue)/\(d.id)", record: nil, deleted: true)) }
    }

    public func pull(since token: SyncToken?) async throws -> SyncPullResult {
        guard available else { throw SyncError.accountUnavailable }
        let since = token.flatMap { Int(String(decoding: $0.raw, as: UTF8.self)) } ?? 0
        var upserts: [SyncRecord] = []
        var deletions: [(kind: SyncKind, id: String)] = []
        var seen: Set<String> = []
        // Walk newest-first so only each key's latest entry in this window counts.
        for entry in log[min(since, log.count)...].reversed() {
            guard seen.insert(entry.key).inserted else { continue }
            if entry.deleted {
                let parts = entry.key.split(separator: "/", maxSplits: 1)
                if parts.count == 2, let kind = SyncKind(rawValue: String(parts[0])) { deletions.append((kind, String(parts[1]))) }
            } else if let r = entry.record {
                upserts.append(r)
            }
        }
        return SyncPullResult(upserts: upserts, deletedIDs: deletions, token: SyncToken(raw: Data(String(log.count).utf8)))
    }

    /// Test/demo helper: simulate a record that arrived from another device, without going through `push`.
    public func seed(_ record: SyncRecord) async {
        log.append(Entry(key: "\(record.kind.rawValue)/\(record.id)", record: record, deleted: false))
    }
}
