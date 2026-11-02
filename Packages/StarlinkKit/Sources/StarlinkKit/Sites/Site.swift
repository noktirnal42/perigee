import Foundation

/// A saved Starlink installation: home, a second property, an RV/Roam dish, a boat. Each site keeps its own
/// history, alert rules and saved stall tests, so switching sites never mixes one install's data into another's.
public struct Site: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var routerHost: String
    public var dishHost: String
    public var createdAt: Date
    /// True only for the single site `SiteStore` creates on first run. It keeps using the app's original,
    /// un-scoped storage location so existing history/alerts/results from before multi-site support shipped
    /// are never orphaned — every other site gets its own storage directory.
    public var isLegacyDefault: Bool

    public init(id: UUID = UUID(), name: String, routerHost: String = "192.168.1.1", dishHost: String = "192.168.100.1",
                createdAt: Date = Date(), isLegacyDefault: Bool = false) {
        self.id = id; self.name = name; self.routerHost = routerHost; self.dishHost = dishHost
        self.createdAt = createdAt; self.isLegacyDefault = isLegacyDefault
    }
}
