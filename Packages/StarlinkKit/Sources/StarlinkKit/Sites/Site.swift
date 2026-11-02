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
    /// When this site's own fields last changed (not its history/alerts/results) — `SiteStore` stamps this,
    /// never the caller, so it stays a reliable "last edited" marker for CloudKit sync's last-write-wins merge.
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, routerHost: String = "192.168.1.1", dishHost: String = "192.168.100.1",
                createdAt: Date = Date(), isLegacyDefault: Bool = false, updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.routerHost = routerHost; self.dishHost = dishHost
        self.createdAt = createdAt; self.isLegacyDefault = isLegacyDefault
        self.updatedAt = updatedAt ?? createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, routerHost, dishHost, createdAt, isLegacyDefault, updatedAt }

    /// Custom decode so sites saved before sync shipped (no `updatedAt` key) load as "last changed at creation"
    /// instead of failing to decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        routerHost = try c.decode(String.self, forKey: .routerHost)
        dishHost = try c.decode(String.self, forKey: .dishHost)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isLegacyDefault = try c.decode(Bool.self, forKey: .isLegacyDefault)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
