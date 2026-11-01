import Foundation

public enum Health: Int, Sendable, Comparable, Codable {
    case good, fair, poor, unknown
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct Verdict: Sendable, Equatable {
    public var health: Health
    public var headline: String
    public var detail: String
}

/// Turns raw counters into plain-language statements. Thresholds are rules of thumb for 5 GHz Wi-Fi gaming.
public enum Advisor {
    public static func radio(_ r: RadioStat) -> Verdict {
        let frames = r.rxPackets + r.rxFrameErrors
        guard frames >= 2_000 else {
            return Verdict(health: .unknown, headline: "Not enough traffic yet",
                           detail: "Only \(frames) frames since boot, too few to judge. Check back after some use.")
        }
        let pct = r.frameErrorRate * 100
        let rate = String(format: "%.1f%%", pct)
        if pct >= 2 {
            return Verdict(health: .poor, headline: "Dropping frames (\(rate))",
                           detail: "Roughly 1 in \(max(1, Int((100 / pct).rounded()))) received frames arrive corrupted. That's classic interference: try another channel or a narrower width.")
        }
        if pct >= 0.5 {
            return Verdict(health: .fair, headline: "Some errors (\(rate))",
                           detail: "Mild interference. Worth a channel change if you see stalls.")
        }
        return Verdict(health: .good, headline: "Clean (\(rate))", detail: "Frame errors are negligible.")
    }

    public static func temperature(_ r: RadioStat) -> Verdict? {
        guard let t = r.temperatureC else { return nil }
        if t >= 80 { return Verdict(health: .poor, headline: "Running hot (\(Int(t))°C)", detail: "Give the router airflow; the radio may throttle.") }
        if t >= 70 { return Verdict(health: .fair, headline: "Warm (\(Int(t))°C)", detail: "Within limits, but keep it ventilated.") }
        return Verdict(health: .good, headline: "Cool (\(Int(t))°C)", detail: "Thermals are fine.")
    }

    public static func signal(rssi: Double?) -> (health: Health, label: String) {
        guard let rssi else { return (.unknown, "—") }
        switch rssi {
        case (-60)...: return (.good, "Excellent")
        case (-70)..<(-60): return (.fair, "Good")
        case (-80)..<(-70): return (.poor, "Weak")
        default: return (.poor, "Very weak")
        }
    }

    public static func client(_ c: NetworkClient) -> Verdict? {
        guard c.isWireless else { return nil }
        let s = signal(rssi: c.rssi)
        if s.health == .poor {
            return Verdict(health: .poor, headline: "\(s.label) signal", detail: "At \(Int(c.rssi ?? 0)) dBm this device is far from the router or blocked by walls. Move it closer or add a mesh node.")
        }
        if c.band == .ghz2, c.rx.rateMbps < 200 {
            return Verdict(health: .fair, headline: "On 2.4 GHz", detail: "Slower and more crowded than 5 GHz. Fine for smart-home gear, not for cloud gaming.")
        }
        return Verdict(health: s.health, headline: "\(s.label) signal", detail: "\(Int(c.rx.rateMbps)) Mbps link rate on \(c.band.label).")
    }

    /// Latency stats over a history window (per-second samples).
    public static func latencyStats(_ series: [Double?]) -> (median: Double?, jitter: Double?, successRate: Double?) {
        let vals = series.compactMap { $0 }
        guard !vals.isEmpty else { return (nil, nil, nil) }
        let sorted = vals.sorted()
        let median = sorted[sorted.count / 2]
        let diffs = zip(vals, vals.dropFirst()).map { abs($1 - $0) }
        let jitter = diffs.isEmpty ? 0 : diffs.reduce(0, +) / Double(diffs.count)
        return (median, jitter, nil)
    }

    public static func successRate(dropRate: [Double?]) -> Double? {
        let v = dropRate.compactMap { $0 }
        guard !v.isEmpty else { return nil }
        return 1 - v.reduce(0, +) / Double(v.count)
    }

    // MARK: Channel advice

    /// 5 GHz primary channels outside the DFS range (radar events on 52–144 force mid-session channel moves = stalls).
    public static let nonDFS5GHz = [36, 40, 44, 48, 149, 153, 157, 161, 165]
    public static func isDFS(channel: Int) -> Bool { (52...144).contains(channel) }
    /// The 80 MHz block a primary channel belongs to.
    public static func block80(of channel: Int) -> ClosedRange<Int>? {
        let blocks = [36...48, 52...64, 100...112, 116...128, 132...144, 149...161]
        return blocks.first { $0.contains(channel) }
    }

    public static func channelAdvice(tuning: WifiTuning, airtime5: BandAirtime?, radio5: RadioStat?) -> [Recommendation] {
        var out: [Recommendation] = []
        let ch = tuning.channel5
        if ch == 0 {
            out.append(.init(severity: .info, title: "5 GHz channel is automatic",
                             detail: "The router picks the channel itself and can move it. Pinning one removes surprise hops mid-game.",
                             suggestion: .channel(.ghz5, 149)))
        } else if isDFS(channel: ch) {
            out.append(.init(severity: .warning, title: "Channel \(ch) is a DFS channel",
                             detail: "If radar is detected the router must leave the channel immediately, which drops every device. Non-DFS channels never do that.",
                             suggestion: .channel(.ghz5, 149)))
        }
        if tuning.dfsEnabled {
            out.append(.init(severity: .warning, title: "DFS is enabled",
                             detail: "Allows radar-shared channels. Turn it off for the steadiest gaming link.",
                             suggestion: .dfs(false)))
        }
        if tuning.vht5 == .mhz160 || tuning.vht5 == .mhz80plus80 {
            out.append(.init(severity: .warning, title: "Channel width is very wide",
                             detail: "160 MHz needs a clean stretch of spectrum and usually hurts reliability. 80 MHz is the sweet spot.",
                             suggestion: .vhtBandwidth(.ghz5, .mhz80)))
        }
        if let r = radio5, Advisor.radio(r).health == .poor {
            let alt = ch >= 149 || ch == 0 ? 36 : 149
            out.append(.init(severity: .warning, title: "5 GHz is dropping frames",
                             detail: "Try the \(alt == 36 ? "36–48" : "149–161") block: channel \(alt), 80 MHz.",
                             suggestion: .channel(.ghz5, alt)))
        }
        if let a = airtime5, a.otherNetworks > 0.25 {
            out.append(.init(severity: .warning, title: "Neighbouring networks use \(Int(a.otherNetworks * 100))% of the air",
                             detail: "Another channel block may be quieter.", suggestion: nil))
        }
        if case .ackSuppression = tuning.traffic {
            out.append(.init(severity: .info, title: "ACK suppression is active",
                             detail: "The router reports ACK suppression. CAKE is another queueing mode; the bandwidth units are not documented in the exported schema.",
                             suggestion: nil))
        } else if case .unset = tuning.traffic {
            out.append(.init(severity: .info, title: "Traffic control isn't configured", detail: "CAKE shaping can tame bufferbloat.", suggestion: nil))
        }
        return out
    }
}

public struct Recommendation: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable { case info, warning }
    public var id: String { title }
    public var severity: Severity
    public var title: String
    public var detail: String
    public var suggestion: WifiSetting?
}
