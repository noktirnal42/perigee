import Testing
import Foundation
@testable import StarlinkKit

@MainActor
@Suite("CloudKit sync")
struct SyncEngineTests {
    private func makeStore(_ dir: URL) -> SiteStore { SiteStore(directory: dir) }
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test("Off by default, and turning it on pushes what's already local")
    func offByDefaultThenPushesOnEnable() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore(tempDir())
        let transport = MockCloudSyncTransport()
        let engine = SyncEngine(siteStore: store, transport: transport, defaults: defaults)
        #expect(engine.isEnabled == false)

        store.update(store.current) // bump updatedAt so there's something to push
        engine.isEnabled = true
        // isEnabled's didSet kicks off sync() in its own Task; awaiting sync() here joins that same pass
        // (SyncEngine.sync()'s in-flight join, not a second one) rather than guessing how long it takes.
        await engine.sync()

        let pulled = try await transport.pull(since: nil)
        #expect(pulled.upserts.contains { $0.id == store.current.id.uuidString })
    }

    @Test("A site saved on another device is pulled in")
    func pullsRemoteSite() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore(tempDir())
        let transport = MockCloudSyncTransport()
        let remote = Site(name: "Lake house", routerHost: "192.168.1.1", dishHost: "192.168.100.1")
        await transport.seed(.init(kind: .site, id: remote.id.uuidString, updatedAt: remote.updatedAt,
                                    payload: try JSONEncoder.iso.encode(remote)))

        let engine = SyncEngine(siteStore: store, transport: transport, defaults: defaults)
        engine.isEnabled = true
        await engine.sync()

        #expect(store.sites.contains { $0.id == remote.id && $0.name == "Lake house" })
    }

    @Test("A newer local edit beats an older remote copy of the same site")
    func localEditWinsOverStaleRemote() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore(tempDir())
        let transport = MockCloudSyncTransport()
        let engine = SyncEngine(siteStore: store, transport: transport, defaults: defaults)
        engine.isEnabled = true
        await engine.sync() // establish a baseline sync so `cutoff` is meaningful

        var edited = store.current
        edited.name = "Renamed locally"
        store.update(edited) // updatedAt = now, after cutoff

        let stale = Site(id: store.current.id, name: "Stale remote name", routerHost: store.current.routerHost,
                          dishHost: store.current.dishHost, createdAt: store.current.createdAt,
                          updatedAt: Date().addingTimeInterval(-3600))
        await transport.seed(.init(kind: .site, id: stale.id.uuidString, updatedAt: stale.updatedAt,
                                    payload: try JSONEncoder.iso.encode(stale)))

        await engine.sync()

        #expect(store.sites.first { $0.id == stale.id }?.name == "Renamed locally")
        // The local edit should also have been pushed back, re-asserting it remotely.
        let afterPull = try await transport.pull(since: nil)
        #expect(afterPull.upserts.first { $0.id == stale.id.uuidString }.flatMap {
            try? JSONDecoder.iso.decode(Site.self, from: $0.payload)
        }?.name == "Renamed locally")
    }

    @Test("A remote deletion removes a site untouched locally since the last sync")
    func remoteDeletionRemovesUntouchedSite() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore(tempDir())
        let second = store.add(Site(name: "Cabin"))
        let transport = MockCloudSyncTransport()
        let engine = SyncEngine(siteStore: store, transport: transport, defaults: defaults)
        engine.isEnabled = true
        await engine.sync() // baseline sync pushes both sites and sets the cutoff

        store.remove(second.id) // simulate the deletion as if it happened on another device by syncing a second store
        await engine.sync()

        let otherStore = makeStore(tempDir())
        let otherEngine = SyncEngine(siteStore: otherStore, transport: transport, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        otherStore.add(second) // this device independently knows about "Cabin" too, untouched since
        otherEngine.isEnabled = true
        await otherEngine.sync()

        #expect(otherStore.sites.contains { $0.id == second.id } == false)
    }
}
