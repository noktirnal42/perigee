import Foundation

public enum HTWidth: Int, Sendable, Codable, CaseIterable, Identifiable {
    case `default` = 0, mhz20 = 1, mhz20or40 = 2
    public var id: Int { rawValue }
    public var label: String { ["Automatic", "20 MHz", "20 / 40 MHz"][rawValue] }
}

public enum VHTWidth: Int, Sendable, Codable, CaseIterable, Identifiable {
    case `default` = 0, disabled = 1, mhz80 = 2, mhz160 = 3, mhz80plus80 = 4
    public var id: Int { rawValue }
    public var label: String { ["Automatic", "Disabled (≤40 MHz)", "80 MHz", "160 MHz", "80+80 MHz"][rawValue] }
}

public enum WirelessModeOption: Int, Sendable, Codable, CaseIterable, Identifiable {
    case `default` = 0, aOnly, bOnly, gOnly, nOnly, bgMixed, anMixed, gnMixed, bgnMixed, aanacMixed, anacMixed, bgnaxMixed, aanacaxMixed
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .default: "Automatic"
        case .aOnly: "802.11a"
        case .bOnly: "802.11b"
        case .gOnly: "802.11g"
        case .nOnly: "802.11n (Wi-Fi 4)"
        case .bgMixed: "b/g"
        case .anMixed: "a/n"
        case .gnMixed: "g/n"
        case .bgnMixed: "b/g/n"
        case .aanacMixed: "a/n/ac"
        case .anacMixed: "n/ac (Wi-Fi 5)"
        case .bgnaxMixed: "b/g/n/ax"
        case .aanacaxMixed: "a/n/ac/ax (Wi-Fi 6)"
        }
    }
    /// Modes that make sense per band — the router happily accepts nonsense, so the UI filters.
    public static func options(for band: RadioBand) -> [WirelessModeOption] {
        switch band {
        case .ghz2: [.default, .bgMixed, .gnMixed, .bgnMixed, .bgnaxMixed]
        default: [.default, .anMixed, .aanacMixed, .anacMixed, .aanacaxMixed]
        }
    }
}

public enum TxPower: Int, Sendable, Codable, CaseIterable, Identifiable {
    case p100 = 0, p80, p50, p25, p12, p6
    public var id: Int { rawValue }
    public var percent: Int { [100, 80, 50, 25, 12, 6][rawValue] }
    public var label: String { "\(percent)%" }
}

public struct CakeParams: Sendable, Equatable, Codable {
    public enum Priority: Int, Sendable, Codable, CaseIterable, Identifiable {
        case diffserv3 = 0, diffserv4, precedence, bestEffort
        public var id: Int { rawValue }
        public var label: String { ["Diffserv 3", "Diffserv 4", "Precedence", "Best effort"][rawValue] }
    }
    public enum AckFilter: Int, Sendable, Codable, CaseIterable, Identifiable {
        case off = 0, on, aggressive
        public var id: Int { rawValue }
        public var label: String { ["Off", "On", "Aggressive"][rawValue] }
    }
    /// Shaping rate in Mbit/s (the proto field is a bare float; the router's own ack queue uses Mbit/s).
    public var bandwidthMbps: Double
    public var priority: Priority
    public var ackFilter: AckFilter
    public var manualRttMs: Double
    public init(bandwidthMbps: Double, priority: Priority = .diffserv3, ackFilter: AckFilter = .off, manualRttMs: Double = 0) {
        self.bandwidthMbps = bandwidthMbps; self.priority = priority; self.ackFilter = ackFilter; self.manualRttMs = manualRttMs
    }
}

public struct AckSuppressionParams: Sendable, Equatable, Codable {
    public var htbAckQueueRate: Double
    public var htbAckQueueCeil: Double
    public var cakeQueueBandwidth: Double
    public var cakeAckFilterAggressive: Bool
    public var cakeManualRttMs: Double
    public init(htbAckQueueRate: Double = 0, htbAckQueueCeil: Double = 0, cakeQueueBandwidth: Double = 0,
                cakeAckFilterAggressive: Bool = false, cakeManualRttMs: Double = 0) {
        self.htbAckQueueRate = htbAckQueueRate; self.htbAckQueueCeil = htbAckQueueCeil
        self.cakeQueueBandwidth = cakeQueueBandwidth; self.cakeAckFilterAggressive = cakeAckFilterAggressive
        self.cakeManualRttMs = cakeManualRttMs
    }
}

public enum TrafficControl: Sendable, Equatable, Codable {
    case unset
    case none
    case ackSuppression(AckSuppressionParams)
    case cake(CakeParams)

    public var label: String {
        switch self {
        case .unset: "Not set"
        case .none: "Off"
        case .ackSuppression: "Ack suppression"
        case .cake(let c): "CAKE · \(Int(c.bandwidthMbps)) Mbps"
        }
    }
}

public struct WifiNetworkInfo: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(networkIndex)-\(bssIndex)" }
    public var networkIndex: Int
    public var bssIndex: Int
    public var ssid: String
    public var band: RadioBand
    public var hidden: Bool
    public var disabled: Bool
    public var isGuest: Bool
    public var security: String
    public var hasPassword: Bool
    public init(networkIndex: Int, bssIndex: Int, ssid: String, band: RadioBand, hidden: Bool, disabled: Bool,
                isGuest: Bool, security: String, hasPassword: Bool) {
        self.networkIndex = networkIndex; self.bssIndex = bssIndex; self.ssid = ssid; self.band = band
        self.hidden = hidden; self.disabled = disabled; self.isGuest = isGuest; self.security = security
        self.hasPassword = hasPassword
    }
}

/// Everything about the router's Wi-Fi/WAN config the app can show or tune. Contains NO passwords.
public struct WifiTuning: Sendable, Equatable, Codable {
    public var countryCode: String = ""
    public var incarnation: UInt64 = 0
    public var channel2: Int = 0
    public var channel5: Int = 0
    public var channel5High: Int = 0
    public var ht2: HTWidth = .default
    public var ht5: HTWidth = .default
    public var ht5High: HTWidth = .default
    public var vht5: VHTWidth = .default
    public var vht5High: VHTWidth = .default
    public var mode2: WirelessModeOption = .default
    public var mode5: WirelessModeOption = .default
    public var mode5High: WirelessModeOption = .default
    public var tx2: TxPower = .p100
    public var tx5: TxPower = .p100
    public var tx5High: TxPower = .p100
    public var dfsEnabled = false
    public var bandSteeringDisabled = false
    public var disable2 = false
    public var disable5 = false
    public var disable5High = false
    public var bypassMode = false
    public var secureDNS = false
    public var outdoorMode = false
    public var customPowerTable = false
    public var nameservers: [String] = []
    public var traffic: TrafficControl = .unset
    public var dscpMark: Int = 0
    public var networks: [WifiNetworkInfo] = []
    public var meshNodeCount: Int = 0
    public init() {}

    public func channel(_ band: RadioBand) -> Int {
        switch band { case .ghz2: channel2; case .ghz5: channel5; case .ghz5High: channel5High; default: 0 }
    }
    public func isDisabled(_ band: RadioBand) -> Bool {
        switch band { case .ghz2: disable2; case .ghz5: disable5; case .ghz5High: disable5High; default: false }
    }
}

public enum ChangeImpact: String, Sendable, Codable {
    case none, wifiRestart, wanShaping, routing
    public var warning: String? {
        switch self {
        case .none: nil
        case .wifiRestart: "Applying this restarts the Wi-Fi radios. Every connected device drops for roughly 10–40 seconds, including this one."
        case .wanShaping: "Changes how the router queues internet traffic. Connections may hiccup for a moment while the queue is rebuilt."
        case .routing: "Changes how the router routes traffic. You can lose access to the router (and the app) until you revert or reset it."
        }
    }
}

public enum ChangeRisk: Int, Sendable, Comparable, Codable {
    case low, medium, high
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
