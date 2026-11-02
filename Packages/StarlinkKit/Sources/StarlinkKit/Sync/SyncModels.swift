import Foundation

/// What's being synced. A plain string-backed enum so this module never needs to import CloudKit — only the
/// real transport implementation (in the app layer) touches `CKRecord`.
public enum SyncKind: String, Sendable, Equatable, Codable { case site }

/// One synced item, framework-agnostic so `SyncEngine`'s merge logic has zero CloudKit dependency.
public struct SyncRecord: Sendable, Codable, Equatable {
    public var kind: SyncKind
    public var id: String
    public var updatedAt: Date
    /// JSON-encoded domain object (currently always a `Site`).
    public var payload: Data
    public init(kind: SyncKind, id: String, updatedAt: Date, payload: Data) {
        self.kind = kind; self.id = id; self.updatedAt = updatedAt; self.payload = payload
    }
}

/// Opaque continuation cursor from the transport's last successful pull (a `CKServerChangeToken` in the real
/// implementation, encoded to `Data`). `nil` means "pull everything" — the first sync, or after a reset.
public struct SyncToken: Sendable, Codable, Equatable {
    public var raw: Data
    public init(raw: Data) { self.raw = raw }
}

public struct SyncPullResult: Sendable {
    public var upserts: [SyncRecord]
    public var deletedIDs: [(kind: SyncKind, id: String)]
    public var token: SyncToken?
    public init(upserts: [SyncRecord], deletedIDs: [(kind: SyncKind, id: String)], token: SyncToken?) {
        self.upserts = upserts; self.deletedIDs = deletedIDs; self.token = token
    }
}

public enum SyncError: Error, Sendable, Equatable, LocalizedError {
    case transportUnavailable
    case accountUnavailable
    case underlying(String)
    public var errorDescription: String? {
        switch self {
        case .transportUnavailable: "Sync isn't available right now."
        case .accountUnavailable: "Sign in to iCloud in Settings to sync between your devices."
        case .underlying(let s): s
        }
    }
}
