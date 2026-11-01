import Foundation

/// The granularity of a stored `HistoryBucket`. Perigee rolls raw samples up to minute buckets as they're
/// recorded, then folds minute buckets into hour buckets and hour buckets into day buckets once they age
/// past retention, so storage stays small forever without ever deleting the trend itself.
public enum HistoryResolution: String, Sendable, Codable, CaseIterable {
    case minute, hour, day
}

/// One polled snapshot, taken at most once per poll tick. Never written to disk directly — `HistoryStore`
/// buckets these into `HistoryBucket`s before persisting.
public struct HistorySample: Sendable, Equatable, Codable {
    public var date: Date
    public var routerReachable: Bool
    public var dishReachable: Bool
    public var internetPingMs: Double?
    public var pingDropRate: Double?
    public var obstructionFraction: Double?
    public var frameErrorRate5: Double?
    public var frameErrorRate2: Double?
    public var clientCount: Int?

    public init(date: Date = Date(), routerReachable: Bool, dishReachable: Bool, internetPingMs: Double? = nil,
                pingDropRate: Double? = nil, obstructionFraction: Double? = nil, frameErrorRate5: Double? = nil,
                frameErrorRate2: Double? = nil, clientCount: Int? = nil) {
        self.date = date; self.routerReachable = routerReachable; self.dishReachable = dishReachable
        self.internetPingMs = internetPingMs; self.pingDropRate = pingDropRate; self.obstructionFraction = obstructionFraction
        self.frameErrorRate5 = frameErrorRate5; self.frameErrorRate2 = frameErrorRate2; self.clientCount = clientCount
    }
}

/// An aggregated time bucket — the unit trend charts draw. Produced by averaging/merging `HistorySample`s
/// (or other buckets, when folding up to a coarser resolution).
public struct HistoryBucket: Sendable, Equatable, Codable, Identifiable {
    public var id: Date { start }
    public var start: Date
    public var resolution: HistoryResolution
    public var sampleCount: Int
    /// Fraction of samples in this bucket where both router and dish answered (0...1).
    public var uptimeFraction: Double
    public var avgPingMs: Double?
    public var minPingMs: Double?
    public var maxPingMs: Double?
    public var avgDropRate: Double?
    public var avgObstruction: Double?
    public var avgFrameErrorRate5: Double?
    public var maxClientCount: Int?

    public init(start: Date, resolution: HistoryResolution, sampleCount: Int, uptimeFraction: Double,
                avgPingMs: Double? = nil, minPingMs: Double? = nil, maxPingMs: Double? = nil,
                avgDropRate: Double? = nil, avgObstruction: Double? = nil, avgFrameErrorRate5: Double? = nil,
                maxClientCount: Int? = nil) {
        self.start = start; self.resolution = resolution; self.sampleCount = sampleCount; self.uptimeFraction = uptimeFraction
        self.avgPingMs = avgPingMs; self.minPingMs = minPingMs; self.maxPingMs = maxPingMs
        self.avgDropRate = avgDropRate; self.avgObstruction = avgObstruction; self.avgFrameErrorRate5 = avgFrameErrorRate5
        self.maxClientCount = maxClientCount
    }

    /// Folds several buckets covering the same coarser period into one, weighting every average by sample count.
    static func merging(_ buckets: [HistoryBucket], start: Date, resolution: HistoryResolution) -> HistoryBucket {
        let totalSamples = buckets.reduce(0) { $0 + $1.sampleCount }
        func weightedAvg(_ pick: (HistoryBucket) -> Double?) -> Double? {
            var sum = 0.0, weight = 0
            for b in buckets { if let v = pick(b) { sum += v * Double(b.sampleCount); weight += b.sampleCount } }
            return weight > 0 ? sum / Double(weight) : nil
        }
        let uptime = totalSamples > 0
            ? buckets.reduce(0.0) { $0 + $1.uptimeFraction * Double($1.sampleCount) } / Double(totalSamples)
            : 0
        return HistoryBucket(
            start: start, resolution: resolution, sampleCount: totalSamples, uptimeFraction: uptime,
            avgPingMs: weightedAvg { $0.avgPingMs },
            minPingMs: buckets.compactMap(\.minPingMs).min(),
            maxPingMs: buckets.compactMap(\.maxPingMs).max(),
            avgDropRate: weightedAvg { $0.avgDropRate },
            avgObstruction: weightedAvg { $0.avgObstruction },
            avgFrameErrorRate5: weightedAvg { $0.avgFrameErrorRate5 },
            maxClientCount: buckets.compactMap(\.maxClientCount).max()
        )
    }
}

/// A marker on the history timeline: a verified tuning/dish change, a refused write, or a saved stall-test
/// run — so a trend chart can show not just "what happened" but "what you changed right before it did."
public struct HistoryAnnotation: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case tuningChange, dishChange, stallTest, writeRefused, custom }
    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var title: String
    public var detail: String

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, title: String, detail: String = "") {
        self.id = id; self.date = date; self.kind = kind; self.title = title; self.detail = detail
    }
}
