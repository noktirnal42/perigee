import Foundation

public enum TuningPreset: String, Sendable, CaseIterable, Identifiable {
    case gaming, balanced, maxThroughput
    public var id: String { rawValue }
    public var title: String {
        switch self { case .gaming: "Gaming"; case .balanced: "Balanced"; case .maxThroughput: "Max throughput" }
    }
    public var tagline: String {
        switch self {
        case .gaming: "Lowest, steadiest latency for cloud gaming."
        case .balanced: "Sensible defaults: stable and fast enough for everything."
        case .maxThroughput: "Widest channels and the most speed, at the cost of stability."
        }
    }
    public var symbol: String {
        switch self { case .gaming: "gamecontroller.fill"; case .balanced: "scalemass.fill"; case .maxThroughput: "bolt.fill" }
    }

    /// The writes needed to move `current` to this preset — only fields that actually differ, in a safe order.
    /// - Parameter shapingMbps: CAKE rate (your real download speed × ~0.9). Nil leaves traffic control alone.
    public func plan(from current: WifiTuning, shapingMbps: Double?) -> [WifiSetting] {
        var wanted: [WifiSetting] = []
        switch self {
        case .gaming:
            wanted += [.dfs(false), .vhtBandwidth(.ghz5, .mhz80), .wirelessMode(.ghz5, .default), .txPower(.ghz5, .p100)]
            if current.channel5 == 0 || Advisor.isDFS(channel: current.channel5) { wanted.append(.channel(.ghz5, 149)) }
            if let r = shapingMbps { wanted.append(.trafficControl(.cake(CakeParams(bandwidth: r, priority: .diffserv4, ackFilter: .on)))) }
        case .balanced:
            wanted += [.dfs(false), .vhtBandwidth(.ghz5, .mhz80), .txPower(.ghz5, .p100), .channel(.ghz5, 0)]
            if let r = shapingMbps { wanted.append(.trafficControl(.cake(CakeParams(bandwidth: r, priority: .diffserv3, ackFilter: .off)))) }
        case .maxThroughput:
            wanted += [.dfs(true), .vhtBandwidth(.ghz5, .mhz160), .txPower(.ghz5, .p100), .channel(.ghz5, 0), .trafficControl(.none)]
        }
        return wanted.filter { !Self.isNoOp($0, in: current) }
    }

    static func isNoOp(_ s: WifiSetting, in t: WifiTuning) -> Bool {
        switch s {
        case .dfs(let v): t.dfsEnabled == v
        case .vhtBandwidth(.ghz5, let w): t.vht5 == w
        case .wirelessMode(.ghz5, let m): t.mode5 == m
        case .txPower(.ghz5, let p): t.tx5 == p
        case .channel(.ghz5, let c): t.channel5 == c
        case .trafficControl(let tc): t.traffic == tc
        default: false
        }
    }
}
