import Foundation

/// How `SyncEngine` reaches whatever actually stores synced records — CloudKit in the app layer, an
/// in-memory stand-in for tests and demo mode. Same protocol-based split as `RouterTransport`/`DishTransport`.
public protocol CloudSyncTransport: Sendable {
    /// Pushes upserts and deletions. Partial failure is acceptable — a failed push just means those records
    /// still look "unsynced" (`updatedAt`/tombstone date after the last successful sync) and get retried next pass.
    func push(upserts: [SyncRecord], deletions: [(kind: SyncKind, id: String)]) async throws

    /// Pulls everything changed since `token` (`nil` = everything, e.g. first sync).
    func pull(since token: SyncToken?) async throws -> SyncPullResult

    /// Whether an account is currently available to sync with — distinct from "sync is turned on". CloudKit's
    /// answer: is the device signed into iCloud with iCloud Drive enabled.
    func accountAvailable() async -> Bool
}
