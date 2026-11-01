import Foundation

/// Where orbital elements come from: a cached download from CelesTrak (public data), else the snapshot bundled with the app.
public actor ConstellationStore {
    public enum Source: Sendable, Equatable { case bundled, cached(Date), downloaded(Date) }
    public private(set) var constellation: Constellation?
    public private(set) var source: Source = .bundled
    public private(set) var lastError: String?

    private let cacheURL: URL
    private static let feed = URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle")!
    private let maxAge: TimeInterval = 6 * 3600

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("starlink.tle")
    }

    /// Loads whatever is available immediately (cache, else bundled), then refreshes from the network if stale.
    @discardableResult
    public func load(allowDownload: Bool = true) async -> Constellation? {
        if constellation == nil {
            if let text = try? String(contentsOf: cacheURL, encoding: .utf8),
               let mod = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date {
                let c = Constellation(tle: text)
                if c.count > 100 { constellation = c; source = .cached(mod) }
            }
            if constellation == nil, let text = Self.bundledText() {
                constellation = Constellation(tle: text); source = .bundled
            }
        }
        let stale: Bool = { if case .downloaded(let d) = source { return Date().timeIntervalSince(d) > maxAge }
                            if case .cached(let d) = source { return Date().timeIntervalSince(d) > maxAge }
                            return true }()
        if allowDownload, stale { await refresh() }
        return constellation
    }

    public func refresh() async {
        do {
            var req = URLRequest(url: Self.feed); req.timeoutInterval = 20
            req.setValue("Perigee/1.0 (unofficial companion app)", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                lastError = "CelesTrak answered with an error."; return
            }
            let c = Constellation(tle: text)
            guard c.count > 1000 else { lastError = "CelesTrak returned too few satellites."; return }
            constellation = c; source = .downloaded(Date()); lastError = nil
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            lastError = "Couldn't refresh satellite data (\(error.localizedDescription)). Using \(source == .bundled ? "the bundled snapshot" : "cached data")."
        }
    }

    static func bundledText() -> String? {
        guard let url = Bundle.module.url(forResource: "starlink-snapshot", withExtension: "tle", subdirectory: "Orbits") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

public enum WorldGeometry {
    /// Coastline polylines as (longitude, latitude) degrees, from Natural Earth 110m (public domain).
    public static let coastlines: [[SIMD2<Float>]] = {
        guard let url = Bundle.module.url(forResource: "coastline", withExtension: "json", subdirectory: "Geo"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]] else { return [] }
        return raw.map { $0.compactMap { $0.count == 2 ? SIMD2<Float>(Float($0[0]), Float($0[1])) : nil } }
    }()
}
