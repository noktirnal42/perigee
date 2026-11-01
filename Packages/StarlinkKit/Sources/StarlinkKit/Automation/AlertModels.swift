import Foundation

/// What an `AlertRule` watches. Reachability metrics are plain on/off; the rest are compared to a threshold.
public enum AlertMetric: String, Sendable, Codable, CaseIterable, Identifiable {
    case routerOffline, dishOffline, obstruction, ping, dropRate, frameErrorRate5

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .routerOffline: "Router offline"
        case .dishOffline: "Dish offline"
        case .obstruction: "Obstruction"
        case .ping: "Ping"
        case .dropRate: "Packet loss"
        case .frameErrorRate5: "5 GHz frame errors"
        }
    }
    /// Reachability alerts ignore the rule's threshold/condition — they fire on "not reachable" alone.
    public var isReachability: Bool { self == .routerOffline || self == .dishOffline }
    public var isFraction: Bool { self == .obstruction || self == .dropRate || self == .frameErrorRate5 }
    public var unit: String { self == .ping ? "ms" : (isFraction ? "%" : "") }
    /// A sensible starting threshold for a new rule on this metric, in the metric's own units (0...1 for fractions).
    public var suggestedThreshold: Double {
        switch self {
        case .routerOffline, .dishOffline: 0.5
        case .obstruction: 0.02
        case .ping: 150
        case .dropRate: 0.05
        case .frameErrorRate5: 0.03
        }
    }

    func value(in sample: HistorySample) -> Double? {
        switch self {
        case .routerOffline: sample.routerReachable ? 0 : 1
        case .dishOffline: sample.dishReachable ? 0 : 1
        case .obstruction: sample.obstructionFraction
        case .ping: sample.internetPingMs
        case .dropRate: sample.pingDropRate
        case .frameErrorRate5: sample.frameErrorRate5
        }
    }
}

public enum AlertCondition: String, Sendable, Codable, CaseIterable {
    case above, below
    public var symbol: String { self == .above ? ">" : "<" }
    func breached(_ value: Double, threshold: Double) -> Bool { self == .above ? value > threshold : value < threshold }
}

/// A local, on-device alert rule: "if `metric` is `condition` `threshold` for at least `sustainedFor`, tell me."
/// Evaluated by `AutomationEngine` against every polled sample — no server, no account, nothing leaves the device.
public struct AlertRule: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var metric: AlertMetric
    public var condition: AlertCondition
    public var threshold: Double
    public var sustainedFor: TimeInterval
    public var enabled: Bool
    public var title: String

    public init(id: UUID = UUID(), metric: AlertMetric, condition: AlertCondition, threshold: Double,
                sustainedFor: TimeInterval = 60, enabled: Bool = true, title: String? = nil) {
        self.id = id; self.metric = metric; self.condition = condition; self.threshold = threshold
        self.sustainedFor = sustainedFor; self.enabled = enabled
        self.title = title ?? AlertRule.defaultTitle(metric: metric, threshold: threshold)
    }

    static func defaultTitle(metric: AlertMetric, threshold: Double) -> String {
        switch metric {
        case .routerOffline: "Router went offline"
        case .dishOffline: "Dish went offline"
        case .obstruction: "Obstruction above \(Int((threshold * 100).rounded()))%"
        case .ping: "Ping above \(Int(threshold.rounded())) ms"
        case .dropRate: "Packet loss above \(Int((threshold * 100).rounded()))%"
        case .frameErrorRate5: "5 GHz frame errors above \(Int((threshold * 100).rounded()))%"
        }
    }

    /// A reasonable starting set, several of them off by default so a fresh install doesn't start noisy.
    public static func defaults() -> [AlertRule] {
        [
            AlertRule(metric: .routerOffline, condition: .above, threshold: 0.5, sustainedFor: 30),
            AlertRule(metric: .dishOffline, condition: .above, threshold: 0.5, sustainedFor: 30),
            AlertRule(metric: .obstruction, condition: .above, threshold: 0.02, sustainedFor: 300),
            AlertRule(metric: .ping, condition: .above, threshold: 150, sustainedFor: 60, enabled: false),
            AlertRule(metric: .dropRate, condition: .above, threshold: 0.05, sustainedFor: 60, enabled: false),
        ]
    }
}

/// A rule that actually fired, with the plain-language message shown in the notification and the timeline.
public struct TriggeredAlert: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var ruleId: UUID
    public var date: Date
    public var title: String
    public var message: String
    public init(id: UUID = UUID(), ruleId: UUID, date: Date = Date(), title: String, message: String) {
        self.id = id; self.ruleId = ruleId; self.date = date; self.title = title; self.message = message
    }
}
