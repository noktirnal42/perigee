import Foundation
import RouterAPI
import SwiftProtobuf

enum WifiTuningMapper {
    static func trafficControl(_ c: WifiConfig) -> TrafficControl {
        switch c.wanTrafficControl {
        case .wanNoTrafficControl(let n):
            n.unknownFields.data.isEmpty ? .none : .opaque(.none, try? n.serializedData())
        case .wanAckSuppression(let a):
            !a.unknownFields.data.isEmpty ? .opaque(.ackSuppression, try? a.serializedData()) : .ackSuppression(AckSuppressionParams(
                htbAckQueueRate: Double(a.htbAckQueueRate), htbAckQueueCeil: Double(a.htbAckQueueCeil),
                cakeQueueBandwidth: Double(a.cakeQueueBandwidth), cakeAckFilterAggressive: a.cakeAckFilterAggressive,
                cakeManualRttMs: Double(a.cakeManualRtt), ackMark: a.ackMark))
        case .wanCakeRateLimit(let k):
            (!k.unknownFields.data.isEmpty || CakeParams.Priority(rawValue: k.priorityQueueParameter.rawValue) == nil || CakeParams.AckFilter(rawValue: k.ackFilter.rawValue) == nil)
            ? .opaque(.cake, try? k.serializedData()) : .cake(CakeParams(
                bandwidth: Double(k.bandwidth),
                priority: CakeParams.Priority(rawValue: k.priorityQueueParameter.rawValue) ?? .diffserv3,
                ackFilter: CakeParams.AckFilter(rawValue: k.ackFilter.rawValue) ?? .off,
                manualRtt: Double(k.manualRtt), hostMark: k.hostMark))
        case nil: .unset
        }
    }

    static func tuning(from c: WifiConfig) -> WifiTuning {
        var t = WifiTuning()
        t.countryCode = c.countryCode
        t.incarnation = c.incarnation
        t.channel2 = Int(c.channel2Ghz); t.channel5 = Int(c.channel5Ghz); t.channel5High = Int(c.channel5GhzHigh)
        t.ht2 = HTWidth(rawValue: c.htBandwidth2Ghz.rawValue) ?? .default
        t.ht5 = HTWidth(rawValue: c.htBandwidth5Ghz.rawValue) ?? .default
        t.ht5High = HTWidth(rawValue: c.htBandwidth5GhzHigh.rawValue) ?? .default
        t.vht5 = VHTWidth(rawValue: c.vhtBandwidth.rawValue) ?? .default
        t.vht5High = VHTWidth(rawValue: c.vhtBandwidth5GhzHigh.rawValue) ?? .default
        t.mode2 = WirelessModeOption(rawValue: c.wirelessMode2Ghz.rawValue) ?? .default
        t.mode5 = WirelessModeOption(rawValue: c.wirelessMode5Ghz.rawValue) ?? .default
        t.mode5High = WirelessModeOption(rawValue: c.wirelessMode5GhzHigh.rawValue) ?? .default
        t.tx2 = TxPower(rawValue: c.txPowerLevel2Ghz.rawValue) ?? .p100
        t.tx5 = TxPower(rawValue: c.txPowerLevel5Ghz.rawValue) ?? .p100
        t.tx5High = TxPower(rawValue: c.txPowerLevel5GhzHigh.rawValue) ?? .p100
        t.dfsEnabled = c.dfsEnabled; t.bandSteeringDisabled = c.disableBandSteering
        t.disable2 = c.disable2Ghz; t.disable5 = c.disable5Ghz; t.disable5High = c.disable5GhzHigh
        t.bypassMode = c.bypassMode; t.secureDNS = c.secureDns; t.outdoorMode = c.outdoorMode
        t.customPowerTable = c.customPowerTable; t.nameservers = c.nameservers
        t.traffic = trafficControl(c); t.dscpMark = Int(c.wanHostDscpMark)
        t.meshNodeCount = c.meshConfigs.count
        for (ni, n) in c.networks.enumerated() {
            for (bi, b) in n.basicServiceSets.enumerated() {
                let band: RadioBand = switch b.band { case .rf2Ghz: .ghz2; case .rf5Ghz: .ghz5; case .rf5GhzHigh: .ghz5High; default: .unknown }
                let (sec, hasPw): (String, Bool) = switch b.auth {
                case .authWpa2Wpa3(let a): ("WPA2/WPA3", !a.password.isEmpty)
                case .authWpa3(let a): ("WPA3", !a.password.isEmpty)
                case .authWpa2(let a): ("WPA2", !a.password.isEmpty)
                case .authOpen: ("Open", false)
                case .authRadius: ("RADIUS", false)
                case .authOpenEncrypted: ("Enhanced Open", false)
                case .authOnboardRadius: ("RADIUS", false)
                case nil: ("—", false)
                }
                t.networks.append(WifiNetworkInfo(networkIndex: ni, bssIndex: bi, ssid: b.ssid, band: band, hidden: b.hidden,
                                                  disabled: b.disable, isGuest: n.guest, security: sec, hasPassword: hasPw))
            }
        }
        return t
    }

    static func password(in c: WifiConfig, network ni: Int, bss bi: Int) -> String? {
        guard c.networks.indices.contains(ni), c.networks[ni].basicServiceSets.indices.contains(bi) else { return nil }
        switch c.networks[ni].basicServiceSets[bi].auth {
        case .authWpa2Wpa3(let a): return a.password
        case .authWpa3(let a): return a.password
        case .authWpa2(let a): return a.password
        default: return nil
        }
    }
}
