import Foundation

/// A window Perigee thinks is worth a heads-up — never a Starlink-published fact, the same honesty standard
/// as the "connected satellite" guess elsewhere in this app: it's Perigee's own estimate from public orbital
/// data and your own on-device history, nothing more.
public struct RiskWindow: Sendable, Equatable, Identifiable {
    public var id: Date { start }
    public var start: Date
    public var end: Date
    public var reasons: [String]
    public init(start: Date, end: Date, reasons: [String]) { self.start = start; self.end = end; self.reasons = reasons }
}

/// Combines two independent, purely heuristic signals into "windows coming up that might be rougher than usual":
/// (1) satellite density — fewer usable satellites over this location than typical for the next few hours, from
/// the same SGP4 propagation the Sky screen already does; (2) historical pattern — hours of day that this
/// device's own stored history shows running worse on average than the rest of the day. Neither is a forecast
/// Starlink publishes; both can be wrong, and both are labeled as estimates everywhere they're shown.
public enum Forecast {
    /// How far ahead to look for an upcoming risk window.
    public static let horizon: TimeInterval = 3 * 3600
    /// Sampling interval for the satellite-density signal.
    public static let step: TimeInterval = 10 * 60

    /// Time windows, over the next `horizon`, where fewer satellites than typical are usable from `observer`.
    public static func satelliteDensityWindows(constellation: Constellation, observer: Observer, from now: Date = Date()) -> [RiskWindow] {
        var samples: [(date: Date, count: Int)] = []
        var t = 0.0
        while t <= horizon {
            let when = now.addingTimeInterval(t)
            samples.append((when, constellation.snapshot(at: when, observer: observer).inView.count))
            t += step
        }
        return windows(fromDensitySamples: samples, step: step)
    }

    /// Pure threshold/run detection, decoupled from `Constellation` so it's testable with synthetic data: finds
    /// contiguous runs of samples whose count falls under 70% of the whole series' mean.
    static func windows(fromDensitySamples samples: [(date: Date, count: Int)], step: TimeInterval) -> [RiskWindow] {
        guard samples.count > 2 else { return [] }
        let mean = Double(samples.reduce(0) { $0 + $1.count }) / Double(samples.count)
        guard mean > 0 else { return [] }
        let threshold = mean * 0.7

        var windows: [RiskWindow] = []
        var runStart: Date?
        for sample in samples {
            if Double(sample.count) < threshold {
                if runStart == nil { runStart = sample.date }
            } else if let start = runStart {
                windows.append(RiskWindow(start: start, end: sample.date, reasons: ["Fewer usable satellites than typical over your location"]))
                runStart = nil
            }
        }
        if let start = runStart, let last = samples.last?.date {
            windows.append(RiskWindow(start: start, end: last.addingTimeInterval(step), reasons: ["Fewer usable satellites than typical over your location"]))
        }
        return windows
    }

    /// Hours of day (local time, 0...23) whose average obstruction or uptime, across all of `buckets`, has
    /// historically run notably worse than the rest of the day. A pattern in your own stored data — not a
    /// prediction, and meaningless until there's at least a day's worth of history to look at.
    static func historicalRiskHours(buckets: [HistoryBucket], calendar: Calendar = .current) -> Set<Int> {
        guard buckets.reduce(0, { $0 + $1.sampleCount }) > 0, buckets.count >= 24 else { return [] }
        var byHour: [Int: (obstruction: Double, uptime: Double, weight: Int)] = [:]
        for b in buckets {
            let hour = calendar.component(.hour, from: b.start)
            var e = byHour[hour] ?? (0, 0, 0)
            if let o = b.avgObstruction { e.obstruction += o * Double(b.sampleCount) }
            e.uptime += b.uptimeFraction * Double(b.sampleCount)
            e.weight += b.sampleCount
            byHour[hour] = e
        }
        let totalWeight = byHour.values.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }
        let avgObstruction = byHour.values.reduce(0.0) { $0 + $1.obstruction } / Double(totalWeight)
        let avgUptime = byHour.values.reduce(0.0) { $0 + $1.uptime } / Double(totalWeight)

        var risky: Set<Int> = []
        for (hour, e) in byHour where e.weight > 0 {
            let hourObstruction = e.obstruction / Double(e.weight)
            let hourUptime = e.uptime / Double(e.weight)
            let obstructedMoreThanUsual = avgObstruction > 0 && hourObstruction > avgObstruction * 1.5
            let lessReliableThanUsual = avgUptime < 1 && hourUptime < avgUptime * 0.98
            if obstructedMoreThanUsual || lessReliableThanUsual { risky.insert(hour) }
        }
        return risky
    }

    /// The upcoming occurrence (within `horizon`) of each historically-risky hour of day, as its own window.
    private static func historicalWindows(buckets: [HistoryBucket], from now: Date, calendar: Calendar) -> [RiskWindow] {
        let risky = historicalRiskHours(buckets: buckets, calendar: calendar)
        guard !risky.isEmpty else { return [] }
        var out: [RiskWindow] = []
        var t = 0.0
        while t <= horizon {
            let when = now.addingTimeInterval(t)
            let hour = calendar.component(.hour, from: when)
            if risky.contains(hour) {
                let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: when) ?? when
                let window = RiskWindow(start: max(hourStart, now), end: hourStart.addingTimeInterval(3600),
                                         reasons: ["This hour of day has historically run rougher in your own history"])
                if !out.contains(where: { calendar.component(.hour, from: $0.start) == hour }) { out.append(window) }
            }
            t += 3600
        }
        return out
    }

    /// Everything worth telling the user about over the next few hours, from both signals, oldest first.
    public static func windows(constellation: Constellation?, observer: Observer?, historyBuckets: [HistoryBucket],
                                from now: Date = Date(), calendar: Calendar = .current) -> [RiskWindow] {
        var out: [RiskWindow] = []
        if let constellation, let observer, observer.isValid {
            out += satelliteDensityWindows(constellation: constellation, observer: observer, from: now)
        }
        out += historicalWindows(buckets: historyBuckets, from: now, calendar: calendar)
        return out.sorted { $0.start < $1.start }
    }
}
