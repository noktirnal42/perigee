import Foundation

/// On-device time-series history: samples recorded during polling are rolled up to minute buckets, then
/// folded into hour and day buckets once they age past retention. Plain JSON files in Application Support,
/// atomic writes, same hygiene as `ResultsStore` — no server, no analytics, nothing leaves the device.
public actor HistoryStore {
    public struct Retention: Sendable {
        /// How long raw minute buckets are kept before folding into hour buckets.
        public var minuteHours: Double
        /// How long hour buckets are kept before folding into day buckets. Day buckets are never folded further.
        public var hourDays: Double
        public init(minuteHours: Double = 48, hourDays: Double = 90) {
            self.minuteHours = minuteHours; self.hourDays = hourDays
        }
    }

    private let minuteURL: URL
    private let hourURL: URL
    private let dayURL: URL
    private let annotationsURL: URL
    private let retention: Retention
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c
    }()

    public private(set) var minuteBuckets: [HistoryBucket] = []
    public private(set) var hourBuckets: [HistoryBucket] = []
    public private(set) var dayBuckets: [HistoryBucket] = []
    public private(set) var annotations: [HistoryAnnotation] = []
    public private(set) var persistenceError: String?
    private var blockedByLoadFailure = false

    /// Set in tests to make retention/compaction deterministic without waiting on the real clock.
    private var clockOverride: Date?

    private var pendingMinuteStart: Date?
    private var pendingSamples: [HistorySample] = []

    public init(directory: URL? = nil, retention: Retention = .init()) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        minuteURL = dir.appendingPathComponent("history-minute.json")
        hourURL = dir.appendingPathComponent("history-hour.json")
        dayURL = dir.appendingPathComponent("history-day.json")
        annotationsURL = dir.appendingPathComponent("history-annotations.json")
        self.retention = retention

        var loadError: String?
        minuteBuckets = Self.load([HistoryBucket].self, from: minuteURL, error: &loadError) ?? []
        hourBuckets = Self.load([HistoryBucket].self, from: hourURL, error: &loadError) ?? []
        dayBuckets = Self.load([HistoryBucket].self, from: dayURL, error: &loadError) ?? []
        annotations = Self.load([HistoryAnnotation].self, from: annotationsURL, error: &loadError) ?? []
        if let loadError {
            blockedByLoadFailure = true
            persistenceError = loadError
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL, error outError: inout String?) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder.iso.decode(T.self, from: Data(contentsOf: url))
        } catch {
            outError = "Existing history could not be read; the files were left untouched."
            return nil
        }
    }

    /// Testing-only clock override so retention/compaction can be exercised without real waiting.
    public func debugSetClock(_ date: Date?) { clockOverride = date }
    private func now() -> Date { clockOverride ?? Date() }

    // MARK: Recording

    /// Record one polled sample. Buckets it into the in-progress minute; only touches disk once that minute finishes.
    public func record(_ sample: HistorySample) {
        let minuteStart = calendar.dateInterval(of: .minute, for: sample.date)?.start ?? sample.date
        if let pending = pendingMinuteStart, pending != minuteStart {
            finalizePendingMinute()
        }
        pendingMinuteStart = minuteStart
        pendingSamples.append(sample)
    }

    /// Flushes the in-progress minute immediately (call before the app backgrounds/terminates).
    public func flush() { finalizePendingMinute() }

    private func finalizePendingMinute() {
        guard let start = pendingMinuteStart, !pendingSamples.isEmpty else { return }
        minuteBuckets.append(aggregate(pendingSamples, start: start, resolution: .minute))
        pendingSamples = []
        pendingMinuteStart = nil
        compact()
        persist()
    }

    private func aggregate(_ samples: [HistorySample], start: Date, resolution: HistoryResolution) -> HistoryBucket {
        let n = samples.count
        let upCount = samples.filter { $0.routerReachable && $0.dishReachable }.count
        func avg(_ pick: (HistorySample) -> Double?) -> Double? {
            let vals = samples.compactMap(pick)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }
        let pings = samples.compactMap(\.internetPingMs)
        return HistoryBucket(
            start: start, resolution: resolution, sampleCount: n,
            uptimeFraction: n > 0 ? Double(upCount) / Double(n) : 0,
            avgPingMs: avg(\.internetPingMs), minPingMs: pings.min(), maxPingMs: pings.max(),
            avgDropRate: avg(\.pingDropRate), avgObstruction: avg(\.obstructionFraction),
            avgFrameErrorRate5: avg(\.frameErrorRate5), maxClientCount: samples.compactMap(\.clientCount).max()
        )
    }

    /// Folds buckets older than retention up into the next coarser resolution, so storage never grows without bound.
    private func compact() {
        minuteBuckets.sort { $0.start < $1.start }
        let minuteCutoff = now().addingTimeInterval(-retention.minuteHours * 3600)
        let toFold = minuteBuckets.prefix { $0.start < minuteCutoff }
        if !toFold.isEmpty {
            let grouped = Dictionary(grouping: toFold) { calendar.dateInterval(of: .hour, for: $0.start)?.start ?? $0.start }
            for (hourStart, group) in grouped {
                if let i = hourBuckets.firstIndex(where: { $0.start == hourStart }) {
                    hourBuckets[i] = HistoryBucket.merging([hourBuckets[i]] + group, start: hourStart, resolution: .hour)
                } else {
                    hourBuckets.append(HistoryBucket.merging(group, start: hourStart, resolution: .hour))
                }
            }
            minuteBuckets.removeFirst(toFold.count)
        }

        hourBuckets.sort { $0.start < $1.start }
        let hourCutoff = now().addingTimeInterval(-retention.hourDays * 86400)
        let toFoldHours = hourBuckets.prefix { $0.start < hourCutoff }
        if !toFoldHours.isEmpty {
            let grouped = Dictionary(grouping: toFoldHours) { calendar.dateInterval(of: .day, for: $0.start)?.start ?? $0.start }
            for (dayStart, group) in grouped {
                if let i = dayBuckets.firstIndex(where: { $0.start == dayStart }) {
                    dayBuckets[i] = HistoryBucket.merging([dayBuckets[i]] + group, start: dayStart, resolution: .day)
                } else {
                    dayBuckets.append(HistoryBucket.merging(group, start: dayStart, resolution: .day))
                }
            }
            hourBuckets.removeFirst(toFoldHours.count)
        }
        dayBuckets.sort { $0.start < $1.start }
    }

    // MARK: Annotations

    public func addAnnotation(_ a: HistoryAnnotation) {
        annotations.insert(a, at: 0)
        if annotations.count > 500 { annotations.removeLast() }
        persist()
    }

    // MARK: Reading

    public func buckets(resolution: HistoryResolution, since: Date) -> [HistoryBucket] {
        let source: [HistoryBucket]
        switch resolution {
        case .minute: source = minuteBuckets
        case .hour: source = hourBuckets
        case .day: source = dayBuckets
        }
        return source.filter { $0.start >= since }
    }

    public func annotations(since: Date) -> [HistoryAnnotation] { annotations.filter { $0.date >= since } }

    /// Sample-weighted uptime fraction across every bucket resolution covering `since` (0...1), or `nil` if there's no data yet.
    public func uptimeFraction(since: Date) -> Double? {
        let all = minuteBuckets.filter { $0.start >= since } + hourBuckets.filter { $0.start >= since } + dayBuckets.filter { $0.start >= since }
        let total = all.reduce(0) { $0 + $1.sampleCount }
        guard total > 0 else { return nil }
        return all.reduce(0.0) { $0 + $1.uptimeFraction * Double($1.sampleCount) } / Double(total)
    }

    public func clearAll() {
        minuteBuckets = []; hourBuckets = []; dayBuckets = []; annotations = []
        pendingSamples = []; pendingMinuteStart = nil
        persistenceError = nil; blockedByLoadFailure = false
        persist()
    }

    private func persist() {
        guard !blockedByLoadFailure else { return }
        do {
            try JSONEncoder.iso.encode(minuteBuckets).write(to: minuteURL, options: .atomic)
            try JSONEncoder.iso.encode(hourBuckets).write(to: hourURL, options: .atomic)
            try JSONEncoder.iso.encode(dayBuckets).write(to: dayURL, options: .atomic)
            try JSONEncoder.iso.encode(annotations).write(to: annotationsURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

extension HistoryStore {
    /// Live data persists under `siteDirectory` (or the app's default Application Support location when `nil`,
    /// e.g. the legacy default site); demo data gets its own throwaway directory per launch so preview/test
    /// numbers never mix into (or overwrite) a real router's history.
    public static func makeDefault(for source: DataSource, siteDirectory: URL? = nil) -> HistoryStore {
        switch source {
        case .live:
            return HistoryStore(directory: siteDirectory)
        case .demo:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeDemoHistory-\(UUID().uuidString)", isDirectory: true)
            return HistoryStore(directory: dir)
        }
    }
}
