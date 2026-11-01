import Foundation
import RouterAPI
import SwiftProtobuf

typealias WifiConfig = RouterAPI.SpaceX_API_Device_WifiConfig

public enum WifiSettingError: Error, Sendable, Equatable, LocalizedError {
    case unsupported(String)
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .unsupported(let s), .invalid(let s): s }
    }
}

/// One user-intent write to the router's Wi-Fi config.
///
/// The invariant that matters: `makeConfig(base:)` returns a `WifiConfig` containing **only** the field being
/// changed plus its matching `apply_<field>` flag — never a copy of the whole config. (The one exception is the
/// SSID-visibility toggle, which must resend the `networks` list because the proto has no finer-grained field.)
public enum WifiSetting: Sendable, Equatable {
    case channel(RadioBand, Int)
    case htBandwidth(RadioBand, HTWidth)
    case vhtBandwidth(RadioBand, VHTWidth)
    case wirelessMode(RadioBand, WirelessModeOption)
    case txPower(RadioBand, TxPower)
    case dfs(Bool)
    case bandSteeringDisabled(Bool)
    case bandDisabled(RadioBand, Bool)
    case bypassMode(Bool)
    case secureDNS(Bool)
    case nameservers([String])
    case outdoorMode(Bool)
    case customPowerTable(Bool)
    case trafficControl(TrafficControl)
    case dscpMark(Int)
    case hiddenSSID(Bool)

    /// Whether this saved value can be written back exactly.
    public var canRestore: Bool {
        switch self {
        case .trafficControl(.unset), .trafficControl(.opaque(_, nil)): false
        default: true
        }
    }

    // MARK: Presentation

    public var title: String {
        switch self {
        case .channel(let b, _): "\(b.label) channel"
        case .htBandwidth(let b, _): "\(b.label) channel width"
        case .vhtBandwidth(let b, _): "\(b.label) channel width"
        case .wirelessMode(let b, _): "\(b.label) wireless mode"
        case .txPower(let b, _): "\(b.label) transmit power"
        case .dfs: "DFS channels"
        case .bandSteeringDisabled: "Band steering"
        case .bandDisabled(let b, _): "\(b.label) radio"
        case .bypassMode: "Bypass mode"
        case .secureDNS: "Secure DNS"
        case .nameservers: "DNS servers"
        case .outdoorMode: "Outdoor mode"
        case .customPowerTable: "Custom power table"
        case .trafficControl: "Traffic control (SQM)"
        case .dscpMark: "WAN DSCP mark"
        case .hiddenSSID: "Hidden network name"
        }
    }

    public var displayValue: String {
        func onOff(_ b: Bool) -> String { b ? "On" : "Off" }
        return switch self {
        case .channel(_, let c): c == 0 ? "Auto" : "Channel \(c)"
        case .htBandwidth(_, let w): w.label
        case .vhtBandwidth(_, let w): w.label
        case .wirelessMode(_, let m): m.label
        case .txPower(_, let p): p.label
        case .dfs(let b): onOff(b)
        case .bandSteeringDisabled(let b): b ? "Disabled" : "Enabled"
        case .bandDisabled(_, let b): b ? "Off" : "On"
        case .bypassMode(let b), .secureDNS(let b), .outdoorMode(let b), .customPowerTable(let b), .hiddenSSID(let b): onOff(b)
        case .nameservers(let n): n.isEmpty ? "Automatic (ISP)" : n.joined(separator: ", ")
        case .trafficControl(let t): t.label
        case .dscpMark(let m): m == 0 ? "Off" : "Mark \(m)"
        }
    }

    public var impact: ChangeImpact {
        switch self {
        case .channel, .htBandwidth, .vhtBandwidth, .wirelessMode, .txPower, .dfs, .bandDisabled, .outdoorMode,
             .customPowerTable, .hiddenSSID, .bandSteeringDisabled:
            .wifiRestart
        case .trafficControl, .dscpMark: .wanShaping
        case .bypassMode: .routing
        case .secureDNS, .nameservers: .none
        }
    }

    public var risk: ChangeRisk {
        switch self {
        case .bypassMode: .high
        case .bandDisabled(_, let off): off ? .high : .medium
        case .channel, .htBandwidth, .vhtBandwidth, .wirelessMode, .txPower, .dfs, .outdoorMode, .customPowerTable,
             .hiddenSSID, .bandSteeringDisabled:
            .medium
        case .trafficControl, .dscpMark, .secureDNS, .nameservers: .low
        }
    }

    /// Proto field name that carries this value (for the change log and tests).
    public var fieldName: String {
        switch self {
        case .channel(let b, _): "channel_" + Self.suffix(b)
        case .htBandwidth(let b, _): "ht_bandwidth_" + Self.suffix(b)
        case .vhtBandwidth(let b, _): b == .ghz5High ? "vht_bandwidth_5ghz_high" : "vht_bandwidth"
        case .wirelessMode(let b, _): "wireless_mode_" + Self.suffix(b)
        case .txPower(let b, _): "tx_power_level_" + Self.suffix(b)
        case .dfs: "dfs_enabled"
        case .bandSteeringDisabled: "disable_band_steering"
        case .bandDisabled(let b, _): "disable_" + Self.suffix(b)
        case .bypassMode: "bypass_mode"
        case .secureDNS: "secure_dns"
        case .nameservers: "nameservers"
        case .outdoorMode: "outdoor_mode"
        case .customPowerTable: "custom_power_table"
        case .trafficControl: "wan_traffic_control"
        case .dscpMark: "wan_host_dscp_mark"
        case .hiddenSSID: "networks"
        }
    }

    static func suffix(_ b: RadioBand) -> String {
        switch b { case .ghz2: "2ghz"; case .ghz5: "5ghz"; case .ghz5High: "5ghz_high"; default: "unknown" }
    }

    // MARK: Reading the current value

    /// The same kind of setting, holding whatever `config` currently has. This is the one-tap revert target.
    func current(in c: WifiConfig) -> WifiSetting {
        switch self {
        case .channel(let b, _):
            .channel(b, Int(b == .ghz2 ? c.channel2Ghz : b == .ghz5 ? c.channel5Ghz : c.channel5GhzHigh))
        case .htBandwidth(let b, _):
            .htBandwidth(b, HTWidth(rawValue: (b == .ghz2 ? c.htBandwidth2Ghz : b == .ghz5 ? c.htBandwidth5Ghz : c.htBandwidth5GhzHigh).rawValue) ?? .default)
        case .vhtBandwidth(let b, _):
            .vhtBandwidth(b, VHTWidth(rawValue: (b == .ghz5High ? c.vhtBandwidth5GhzHigh : c.vhtBandwidth).rawValue) ?? .default)
        case .wirelessMode(let b, _):
            .wirelessMode(b, WirelessModeOption(rawValue: (b == .ghz2 ? c.wirelessMode2Ghz : b == .ghz5 ? c.wirelessMode5Ghz : c.wirelessMode5GhzHigh).rawValue) ?? .default)
        case .txPower(let b, _):
            .txPower(b, TxPower(rawValue: (b == .ghz2 ? c.txPowerLevel2Ghz : b == .ghz5 ? c.txPowerLevel5Ghz : c.txPowerLevel5GhzHigh).rawValue) ?? .p100)
        case .dfs: .dfs(c.dfsEnabled)
        case .bandSteeringDisabled: .bandSteeringDisabled(c.disableBandSteering)
        case .bandDisabled(let b, _): .bandDisabled(b, b == .ghz2 ? c.disable2Ghz : b == .ghz5 ? c.disable5Ghz : c.disable5GhzHigh)
        case .bypassMode: .bypassMode(c.bypassMode)
        case .secureDNS: .secureDNS(c.secureDns)
        case .nameservers: .nameservers(c.nameservers)
        case .outdoorMode: .outdoorMode(c.outdoorMode)
        case .customPowerTable: .customPowerTable(c.customPowerTable)
        case .trafficControl: .trafficControl(WifiTuningMapper.trafficControl(c))
        case .dscpMark: .dscpMark(Int(c.wanHostDscpMark))
        case .hiddenSSID:
            .hiddenSSID(c.networks.first(where: { !$0.guest })?.basicServiceSets.contains(where: { $0.hidden }) ?? false)
        }
    }

    // MARK: Building the request

    /// A `WifiConfig` holding exactly this one change and its `apply_` flag.
    func makeConfig(base: WifiConfig) throws -> WifiConfig {
        var c = WifiConfig()
        switch self {
        case .channel(let b, let v):
            guard v >= 0, v <= 233 else { throw WifiSettingError.invalid("Channel \(v) is out of range.") }
            switch b {
            case .ghz2: c.channel2Ghz = UInt32(v); c.applyChannel2Ghz = true
            case .ghz5: c.channel5Ghz = UInt32(v); c.applyChannel5Ghz = true
            case .ghz5High: c.channel5GhzHigh = UInt32(v); c.applyChannel5GhzHigh = true
            default: throw WifiSettingError.unsupported("No such radio.")
            }
        case .htBandwidth(let b, let w):
            let v = SpaceX_API_Device_WifiConfig.HTBandwidth(rawValue: w.rawValue) ?? .default
            switch b {
            case .ghz2: c.htBandwidth2Ghz = v; c.applyHtBandwidth2Ghz = true
            case .ghz5: c.htBandwidth5Ghz = v; c.applyHtBandwidth5Ghz = true
            case .ghz5High: c.htBandwidth5GhzHigh = v; c.applyHtBandwidth5GhzHigh = true
            default: throw WifiSettingError.unsupported("No such radio.")
            }
        case .vhtBandwidth(let b, let w):
            let v = SpaceX_API_Device_WifiConfig.VHTBandwidth(rawValue: w.rawValue) ?? .default
            switch b {
            case .ghz5: c.vhtBandwidth = v; c.applyVhtBandwidth = true
            case .ghz5High: c.vhtBandwidth5GhzHigh = v; c.applyVhtBandwidth5GhzHigh = true
            default: throw WifiSettingError.unsupported("80/160 MHz widths only exist on 5 GHz radios.")
            }
        case .wirelessMode(let b, let m):
            let v = SpaceX_API_Device_WifiConfig.WirelessMode(rawValue: m.rawValue) ?? .default
            switch b {
            case .ghz2: c.wirelessMode2Ghz = v; c.applyWirelessMode2Ghz = true
            case .ghz5: c.wirelessMode5Ghz = v; c.applyWirelessMode5Ghz = true
            case .ghz5High: c.wirelessMode5GhzHigh = v; c.applyWirelessMode5GhzHigh = true
            default: throw WifiSettingError.unsupported("No such radio.")
            }
        case .txPower(let b, let p):
            let v = SpaceX_API_Device_TxPowerLevel(rawValue: p.rawValue) ?? .txPowerLevel100
            switch b {
            case .ghz2: c.txPowerLevel2Ghz = v; c.applyTxPowerLevel2Ghz = true
            case .ghz5: c.txPowerLevel5Ghz = v; c.applyTxPowerLevel5Ghz = true
            case .ghz5High: c.txPowerLevel5GhzHigh = v; c.applyTxPowerLevel5GhzHigh = true
            default: throw WifiSettingError.unsupported("No such radio.")
            }
        case .dfs(let v): c.dfsEnabled = v; c.applyDfsEnabled = true
        case .bandSteeringDisabled(let v): c.disableBandSteering = v; c.applyDisableBandSteering = true
        case .bandDisabled(let b, let v):
            switch b {
            case .ghz2: c.disable2Ghz = v; c.applyDisable2Ghz = true
            case .ghz5: c.disable5Ghz = v; c.applyDisable5Ghz = true
            case .ghz5High: c.disable5GhzHigh = v; c.applyDisable5GhzHigh = true
            default: throw WifiSettingError.unsupported("No such radio.")
            }
        case .bypassMode(let v): c.bypassMode = v; c.applyBypassMode = true
        case .secureDNS(let v): c.secureDns = v; c.applySecureDns = true
        case .nameservers(let n):
            for s in n where !Self.isIPAddress(s) { throw WifiSettingError.invalid("“\(s)” is not an IP address.") }
            c.nameservers = n; c.applyNameservers = true
        case .outdoorMode(let v): c.outdoorMode = v; c.applyOutdoorMode = true
        case .customPowerTable(let v): c.customPowerTable = v; c.applyCustomPowerTable = true
        case .dscpMark(let m):
            guard (0...63).contains(m) else { throw WifiSettingError.invalid("DSCP marks are 0–63.") }
            c.wanHostDscpMark = Int32(m); c.applyWanHostDscpMark = true
        case .trafficControl(let t):
            switch t {
            case .unset: throw WifiSettingError.unsupported("“Not set” can't be written back; choose Off, Ack suppression or CAKE.")
            case .none: c.wanNoTrafficControl = SpaceX_API_Device_NoTrafficControl()
            case .opaque(let kind, let data):
                guard let data else { throw WifiSettingError.unsupported("The original traffic-control setting could not be preserved.") }
                switch kind {
                case .none: c.wanNoTrafficControl = try SpaceX_API_Device_NoTrafficControl(serializedBytes: data)
                case .ackSuppression: c.wanAckSuppression = try SpaceX_API_Device_AckSuppression(serializedBytes: data)
                case .cake: c.wanCakeRateLimit = try SpaceX_API_Device_CakeRateLimit(serializedBytes: data)
                }
            case .ackSuppression(let a):
                var m = SpaceX_API_Device_AckSuppression()
                m.ackMark = a.ackMark
                m.htbAckQueueRate = Float(a.htbAckQueueRate); m.htbAckQueueCeil = Float(a.htbAckQueueCeil)
                m.cakeQueueBandwidth = Float(a.cakeQueueBandwidth); m.cakeAckFilterAggressive = a.cakeAckFilterAggressive
                m.cakeManualRtt = Float(a.cakeManualRttMs)
                c.wanAckSuppression = m
            case .cake(let p):
                guard p.bandwidth.isFinite, p.bandwidth > 0, Float(p.bandwidth).isFinite,
                      p.manualRtt.isFinite, p.manualRtt >= 0, Float(p.manualRtt).isFinite else {
                    throw WifiSettingError.invalid("CAKE values must be finite; bandwidth must be greater than zero.")
                }
                var m = SpaceX_API_Device_CakeRateLimit()
                m.hostMark = p.hostMark
                m.bandwidth = Float(p.bandwidth)
                m.priorityQueueParameter = SpaceX_API_Device_CakePriorityQueueParameter(rawValue: p.priority.rawValue) ?? .diffserv3
                m.ackFilter = SpaceX_API_Device_CakeAckFilter(rawValue: p.ackFilter.rawValue) ?? .noAckFilter
                m.manualRtt = Float(p.manualRtt)
                c.wanCakeRateLimit = m
            }
            c.applyWanTrafficControl = true
        case .hiddenSSID(let hidden):
            // The proto has no per-SSID flag: resend the networks list with the primary network's `hidden` changed.
            var nets = base.networks
            guard let idx = nets.firstIndex(where: { !$0.guest }) else { throw WifiSettingError.unsupported("No primary network found.") }
            for i in nets[idx].basicServiceSets.indices { nets[idx].basicServiceSets[i].hidden = hidden }
            c.networks = nets; c.applyNetworks = true
        }
        return c
    }

    static func isIPAddress(_ s: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, s, &v4) == 1 || inet_pton(AF_INET6, s, &v6) == 1
    }
}
