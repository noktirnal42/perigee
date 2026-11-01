import Foundation

/// A digest built from `HistoryStore` data: "what did the last week look like." Computed on demand (e.g. once
/// a week, or whenever the user opens Trends) rather than pushed from a server — there is no server.
public struct WeeklyRecap: Sendable, Equatable, Codable {
    public var periodStart: Date
    public var periodEnd: Date
    public var uptimeFraction: Double?
    public var avgPingMs: Double?
    public var avgObstruction: Double?
    public var worstHourStart: Date?
    public var worstHourAvgPingMs: Double?
    public var bestHourStart: Date?
    public var bestHourAvgPingMs: Double?

    public init(periodStart: Date, periodEnd: Date, uptimeFraction: Double? = nil, avgPingMs: Double? = nil,
                avgObstruction: Double? = nil, worstHourStart: Date? = nil, worstHourAvgPingMs: Double? = nil,
                bestHourStart: Date? = nil, bestHourAvgPingMs: Double? = nil) {
        self.periodStart = periodStart; self.periodEnd = periodEnd; self.uptimeFraction = uptimeFraction
        self.avgPingMs = avgPingMs; self.avgObstruction = avgObstruction
        self.worstHourStart = worstHourStart; self.worstHourAvgPingMs = worstHourAvgPingMs
        self.bestHourStart = bestHourStart; self.bestHourAvgPingMs = bestHourAvgPingMs
    }

    /// One short paragraph, suitable for a notification body or a card on the Trends screen.
    public var summary: String {
        var parts: [String] = []
        if let u = uptimeFraction { parts.append(String(format: "%.2f%% uptime", u * 100)) }
        if let p = avgPingMs { parts.append(String(format: "avg ping %.0f ms", p)) }
        if let o = avgObstruction, o > 0 { parts.append(String(format: "%.2f%% average obstruction", o * 100)) }
        var s = parts.isEmpty ? "Not enough history yet for a recap." : "This week: " + parts.joined(separator: ", ") + "."
        if let w = worstHourStart, let wp = worstHourAvgPingMs {
            s += String(format: " Worst hour was around %@ (avg %.0f ms).", Self.hourFormatter.string(from: w), wp)
        }
        return s
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h a"; return f
    }()

    /// Builds a recap for the 7 days ending at `now`, reading hour buckets for the best/worst-hour comparison
    /// (minute buckets haven't been grouped by hour yet, and day buckets are too coarse for that).
    public static func compute(from store: HistoryStore, now: Date = Date()) async -> WeeklyRecap? {
        let start = now.addingTimeInterval(-7 * 86400)
        let hours = await store.buckets(resolution: .hour, since: start)
        let minutes = await store.buckets(resolution: .minute, since: start)
        let all = hours + minutes
        guard !all.isEmpty else { return nil }

        func weightedAvg(_ pick: (HistoryBucket) -> Double?) -> Double? {
            var sum = 0.0, weight = 0
            for b in all { if let v = pick(b) { sum += v * Double(b.sampleCount); weight += b.sampleCount } }
            return weight > 0 ? sum / Double(weight) : nil
        }
        let hourSamples = hours.filter { $0.avgPingMs != nil }
        let worst = hourSamples.max { ($0.avgPingMs ?? 0) < ($1.avgPingMs ?? 0) }
        let best = hourSamples.min { ($0.avgPingMs ?? .infinity) < ($1.avgPingMs ?? .infinity) }

        return WeeklyRecap(
            periodStart: start, periodEnd: now,
            uptimeFraction: await store.uptimeFraction(since: start),
            avgPingMs: weightedAvg { $0.avgPingMs }, avgObstruction: weightedAvg { $0.avgObstruction },
            worstHourStart: worst?.start, worstHourAvgPingMs: worst?.avgPingMs,
            bestHourStart: best?.start, bestHourAvgPingMs: best?.avgPingMs
        )
    }
}
