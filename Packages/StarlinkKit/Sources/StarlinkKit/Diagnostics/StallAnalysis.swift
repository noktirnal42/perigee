import Foundation

/// Port of `reference/ab.sh`: a 30 s ping run at 0.2 s intervals, summarised as loss / median / p95 / stall episodes.
public struct StallResult: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var label: String
    public var target: String
    public var interval: TimeInterval
    public var rttMs: [Double?]           // index = sequence number; nil = lost
    public var lossPercent: Double
    public var medianMs: Double
    public var p95Ms: Double
    public var maxMs: Double
    public var episodes: Int
    public var averageGapSeconds: Double?
    public var stallThresholdMs: Double
    public var settings: SettingsSnapshot?

    /// What the router was configured to at the time, so A/B charts can say *why* two runs differ.
    public struct SettingsSnapshot: Sendable, Equatable, Codable {
        public var summary: String
        public init(summary: String) { self.summary = summary }
    }

    public var verdict: StallVerdict { StallVerdict(self) }
}

public enum StallAnalysis {
    /// Same algorithm as ab.sh: a sample is "bad" if it was lost or slower than `threshold`;
    /// bad samples closer than `episodeGap` seconds belong to one stall episode.
    public static func analyze(rtt: [Double?], interval: TimeInterval = 0.2, target: String, label: String,
                               threshold: Double = 20, episodeGap: TimeInterval = 1.0,
                               settings: StallResult.SettingsSnapshot? = nil, date: Date = Date()) -> StallResult {
        let got = rtt.compactMap { $0 }
        let n = rtt.count
        var badTimes: [Double] = []
        for (i, v) in rtt.enumerated() where v == nil || v! > threshold { badTimes.append(Double(i) * interval) }
        var episodes: [[Double]] = []
        for t in badTimes {
            if var last = episodes.last, let end = last.last, t - end <= episodeGap {
                last.append(t); episodes[episodes.count - 1] = last
            } else { episodes.append([t]) }
        }
        let starts = episodes.compactMap(\.first)
        let gaps = zip(starts, starts.dropFirst()).map { $1 - $0 }
        let sorted = got.sorted()
        let median: Double = sorted.isEmpty ? 0 : (sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2)
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return StallResult(
            id: UUID(), date: date, label: label, target: target, interval: interval, rttMs: rtt,
            lossPercent: n == 0 ? 0 : 100 * Double(n - got.count) / Double(n),
            medianMs: median, p95Ms: p95, maxMs: sorted.last ?? 0, episodes: episodes.count,
            averageGapSeconds: gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count),
            stallThresholdMs: threshold, settings: settings)
    }
}

/// Plain-language reading of a run.
public struct StallVerdict: Sendable, Equatable {
    public enum Grade: Int, Sendable, Comparable { case great, ok, poor, bad
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    public var grade: Grade
    public var headline: String
    public var detail: String

    init(_ r: StallResult) {
        if r.lossPercent >= 3 || r.episodes >= 8 || r.p95Ms > 150 {
            grade = .bad
            headline = "Stalling"
            detail = "Expect rubber-banding and freezes in cloud gaming. \(r.episodes) stall\(r.episodes == 1 ? "" : "s"), \(String(format: "%.1f", r.lossPercent))% loss."
        } else if r.lossPercent >= 1 || r.episodes >= 3 || r.p95Ms > 60 {
            grade = .poor
            headline = "Unstable"
            detail = "Noticeable hiccups. Try a different channel, a narrower width, or CAKE traffic shaping."
        } else if r.p95Ms > 25 || r.episodes >= 1 {
            grade = .ok
            headline = "Mostly smooth"
            detail = "Occasional blips, fine for most uses."
        } else {
            grade = .great
            headline = "Rock solid"
            detail = "No loss and tight latency. Ideal for cloud gaming."
        }
    }
}
