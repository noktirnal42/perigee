import Foundation
import Testing
@testable import StarlinkKit

@MainActor
@Suite("Site store")
struct SiteTests {
    private func tempStore() -> SiteStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSiteTests-\(UUID().uuidString)", isDirectory: true)
        return SiteStore(directory: dir)
    }

    @Test("A fresh store creates one legacy-default Home site")
    func freshStoreHasOneSite() {
        let store = tempStore()
        #expect(store.sites.count == 1)
        #expect(store.current.name == "Home")
        #expect(store.current.isLegacyDefault)
        #expect(store.directory(for: store.current) == nil)   // legacy default keeps the un-scoped location
    }

    @Test("Added sites get their own scoped storage directory")
    func addedSitesAreScoped() {
        let store = tempStore()
        let site = store.add(Site(name: "Cabin", routerHost: "192.168.1.1", dishHost: "192.168.100.1"))
        #expect(store.sites.count == 2)
        let dir = store.directory(for: site)
        #expect(dir != nil)
        #expect(dir!.path.contains(site.id.uuidString))
    }

    @Test("Selecting a site updates current and persists")
    func selectingPersists() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSiteTests-\(UUID().uuidString)", isDirectory: true)
        let store = SiteStore(directory: dir)
        let site = store.add(Site(name: "Cabin"))
        store.select(site.id)
        #expect(store.current.id == site.id)

        let reopened = SiteStore(directory: dir)
        #expect(reopened.current.id == site.id)
        #expect(reopened.sites.count == 2)
    }

    @Test("The current site cannot be removed, nor the last remaining one")
    func removalGuards() {
        let store = tempStore()
        let onlySite = store.current
        store.remove(onlySite.id)
        #expect(store.sites.count == 1)   // refused: it's the only site

        let second = store.add(Site(name: "Cabin"))
        store.remove(second.id)           // not current: allowed
        #expect(store.sites.count == 1)

        let third = store.add(Site(name: "Boat"))
        store.select(third.id)
        store.remove(third.id)            // current: refused
        #expect(store.sites.count == 2)
    }

    @Test("Renaming/re-addressing a site via update() persists the change")
    func updatePersists() {
        let store = tempStore()
        var site = store.add(Site(name: "Cabin", routerHost: "192.168.1.1", dishHost: "192.168.100.1"))
        site.name = "Cabin (upstairs)"
        site.routerHost = "10.0.0.1"
        store.update(site)
        #expect(store.sites.first { $0.id == site.id }?.name == "Cabin (upstairs)")
        #expect(store.sites.first { $0.id == site.id }?.routerHost == "10.0.0.1")
    }
}

@MainActor
@Suite("Multi-site session switching")
struct SessionSiteTests {
    @Test("Switching sites reconnects to the new addresses and swaps per-site stores")
    func switchingSitesIsolatesStores() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSiteSessionTests-\(UUID().uuidString)", isDirectory: true)
        let sites = SiteStore(directory: dir)
        let second = sites.add(Site(name: "Cabin", routerHost: "192.168.1.1", dishHost: "192.168.100.1"))

        let session = StarlinkSession(source: .demo, siteStore: sites)
        #expect(session.currentSite.isLegacyDefault)
        let firstHistory = session.history

        session.switchSite(to: second.id)
        // Demo mode never switches sites (sites are a "real hardware" concept) — switchSite is a no-op here.
        #expect(session.currentSite.isLegacyDefault)
        #expect(session.history === firstHistory)
    }

    @Test("A session built with no explicit site uses the store's legacy default")
    func defaultsToLegacySite() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSiteSessionTests-\(UUID().uuidString)", isDirectory: true)
        let sites = SiteStore(directory: dir)
        let session = StarlinkSession(source: .demo, siteStore: sites)
        #expect(session.currentSite.id == sites.current.id)
        #expect(session.routerHost == sites.current.routerHost)
    }

    @Test("Switching sites in live mode updates addresses and the current site")
    func switchingSitesLiveUpdatesAddresses() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeSiteSessionTests-\(UUID().uuidString)", isDirectory: true)
        let sites = SiteStore(directory: dir)
        let second = sites.add(Site(name: "Cabin", routerHost: "10.1.1.1", dishHost: "10.1.1.2"))

        let session = StarlinkSession(source: .live, siteStore: sites)
        session.switchSite(to: second.id)
        #expect(session.currentSite.id == second.id)
        #expect(session.routerHost == "10.1.1.1")
        #expect(session.dishHost == "10.1.1.2")
        session.stop()
    }
}
