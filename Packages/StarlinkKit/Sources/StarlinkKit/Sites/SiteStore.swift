import Foundation
import Observation

/// Saved sites plus which one is current. Plain JSON in Application Support, same hygiene as every other
/// store here — no server, no account. `@MainActor`/`@Observable` (not an actor) because this is small,
/// user-driven config read directly by SwiftUI, not a high-frequency data store like `HistoryStore`.
@MainActor
@Observable
public final class SiteStore {
    private struct Payload: Codable { var sites: [Site]; var currentSiteId: UUID }

    private let url: URL
    public private(set) var sites: [Site]
    public private(set) var currentSiteId: UUID
    public private(set) var persistenceError: String?
    private var blockedByLoadFailure = false

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sites.json")

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let payload = try JSONDecoder.iso.decode(Payload.self, from: Data(contentsOf: url))
                sites = payload.sites
                currentSiteId = payload.currentSiteId
            } catch {
                blockedByLoadFailure = true
                persistenceError = "Existing sites could not be read; the file was left untouched."
                let fallback = Site(name: "Home", isLegacyDefault: true)
                sites = [fallback]; currentSiteId = fallback.id
            }
        } else {
            let fallback = Site(name: "Home", isLegacyDefault: true)
            sites = [fallback]
            currentSiteId = fallback.id
        }
    }

    public var current: Site { sites.first { $0.id == currentSiteId } ?? sites[0] }

    @discardableResult
    public func add(_ site: Site) -> Site {
        sites.append(site)
        persist()
        return site
    }

    /// Does nothing if `id` is the only remaining site, or the currently-selected one — switch away first.
    public func remove(_ id: UUID) {
        guard sites.count > 1, id != currentSiteId else { return }
        sites.removeAll { $0.id == id }
        persist()
    }

    public func update(_ site: Site) {
        guard let i = sites.firstIndex(where: { $0.id == site.id }) else { return }
        sites[i] = site
        persist()
    }

    public func select(_ id: UUID) {
        guard sites.contains(where: { $0.id == id }) else { return }
        currentSiteId = id
        persist()
    }

    /// Storage directory for a site's history/alerts/results: `nil` for the legacy default site (so it keeps
    /// using the app's original un-scoped location), a dedicated `Sites/<uuid>/` folder for every other site.
    public func directory(for site: Site) -> URL? {
        guard !site.isLegacyDefault else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
            .appendingPathComponent("Sites", isDirectory: true)
            .appendingPathComponent(site.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func persist() {
        guard !blockedByLoadFailure else { return }
        do {
            try JSONEncoder.iso.encode(Payload(sites: sites, currentSiteId: currentSiteId)).write(to: url, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}
