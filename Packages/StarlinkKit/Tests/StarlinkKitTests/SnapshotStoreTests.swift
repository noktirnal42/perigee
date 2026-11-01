import Foundation
import Testing
@testable import StarlinkKit

@Suite("Snapshot store")
struct SnapshotStoreTests {
    @Test("A written snapshot reads back unchanged")
    func roundTrips() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Whole seconds: ISO 8601 round-tripping (JSONEncoder.iso) drops sub-second precision.
        let snapshot = StatusSnapshot(updatedAt: Date(timeIntervalSince1970: 1_700_000_000), status: .online,
                                       statusText: "Online", internetPingMs: 23, obstructionFraction: 0.001, clientCount: 4)
        SnapshotStore.write(snapshot, directory: dir)
        #expect(SnapshotStore.read(directory: dir) == snapshot)
    }

    @Test("Reading before anything is written returns nil, not a crash")
    func nilWhenMissing() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        #expect(SnapshotStore.read(directory: dir) == nil)
    }

    @Test("A later write replaces the earlier one")
    func overwrites() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SnapshotStore.write(.init(status: .online, statusText: "Online"), directory: dir)
        SnapshotStore.write(.init(status: .offline, statusText: "Offline"), directory: dir)
        #expect(SnapshotStore.read(directory: dir)?.status == .offline)
    }
}
