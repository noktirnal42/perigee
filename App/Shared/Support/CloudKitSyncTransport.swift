import Foundation
import CloudKit
import StarlinkKit

/// CloudKit-backed `CloudSyncTransport`: the user's own private database, one custom zone. This is Apple's
/// infrastructure between this person's own signed-in devices — never a Perigee-run server, and nothing here
/// is reachable by, or shared with, anyone else (SPEC_v2.md §4F/§J).
actor CloudKitSyncTransport: CloudSyncTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var zoneReady = false

    init(containerIdentifier: String = "iCloud.dev.noktirnal.perigee") {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: "PerigeeSync", ownerName: CKCurrentUserDefaultName)
    }

    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        zoneReady = true
    }

    func push(upserts: [SyncRecord], deletions: [(kind: SyncKind, id: String)]) async throws {
        guard !upserts.isEmpty || !deletions.isEmpty else { return }
        try await ensureZone()
        let records: [CKRecord] = upserts.map { r in
            let record = CKRecord(recordType: r.kind.rawValue, recordID: Self.recordID(r.kind, r.id, zoneID))
            record["updatedAt"] = r.updatedAt as CKRecordValue
            record["payload"] = r.payload as CKRecordValue
            return record
        }
        let deleteIDs = deletions.map { Self.recordID($0.kind, $0.id, zoneID) }
        _ = try await database.modifyRecords(saving: records, deleting: deleteIDs, savePolicy: .changedKeys)
    }

    func pull(since token: SyncToken?) async throws -> SyncPullResult {
        try await ensureZone()
        var changeToken = token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0.raw) }
        var upserts: [SyncRecord] = []
        var deletions: [(kind: SyncKind, id: String)] = []
        var moreComing = true

        while moreComing {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: changeToken)
            for (_, outcome) in result.modificationResultsByID {
                guard case .success(let modification) = outcome else { continue }
                let record = modification.record
                guard let kind = SyncKind(rawValue: record.recordType),
                      let updatedAt = record["updatedAt"] as? Date,
                      let payload = record["payload"] as? Data,
                      let id = Self.id(from: record.recordID, kind: kind) else { continue }
                upserts.append(SyncRecord(kind: kind, id: id, updatedAt: updatedAt, payload: payload))
            }
            for deletion in result.deletions {
                guard let kind = SyncKind(rawValue: deletion.recordType), let id = Self.id(from: deletion.recordID, kind: kind) else { continue }
                deletions.append((kind, id))
            }
            changeToken = result.changeToken
            moreComing = result.moreComing
        }

        let tokenData = changeToken.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        return SyncPullResult(upserts: upserts, deletedIDs: deletions, token: tokenData.map(SyncToken.init(raw:)))
    }

    private static func recordID(_ kind: SyncKind, _ id: String, _ zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(kind.rawValue)-\(id)", zoneID: zoneID)
    }
    private static func id(from recordID: CKRecord.ID, kind: SyncKind) -> String? {
        let prefix = "\(kind.rawValue)-"
        guard recordID.recordName.hasPrefix(prefix) else { return nil }
        return String(recordID.recordName.dropFirst(prefix.count))
    }
}
