import Foundation

/// Maps protobuf-JSON documents from the router into domain models. Pure functions → easy to fixture-test.
enum RouterMapper {
    static func identity(_ info: JSONValue, state: JSONValue) -> DeviceIdentity {
        DeviceIdentity(
            id: info["id"].string ?? "", hardwareVersion: info["hardwareVersion"].string ?? "",
            softwareVersion: info["softwareVersion"].string ?? "", countryCode: info["countryCode"].string ?? "",
            bootCount: info["bootcount"].int ?? 0, uptime: state["uptimeS"].double ?? 0)
    }

    static func alertNames(_ alerts: JSONValue) -> [String] {
        alerts.keys.filter { alerts[$0].bool == true }.map(prettify)
    }

    static func prettify(_ camel: String) -> String {
        var out = ""
        for (i, ch) in camel.enumerated() {
            if ch.isUppercase, i > 0 { out.append(" ") }
            out.append(i == 0 ? Character(ch.uppercased()) : Character(ch.lowercased()))
        }
        return out
    }

    static func airtime(_ b: JSONValue) -> BandAirtime? {
        guard b.exists else { return nil }
        return BandAirtime(busy: b["chanBusyTimeFraction"].double ?? 0, tx: b["txAirTimeFraction"].double ?? 0,
                           rx: b["rxAirTimeFraction"].double ?? 0, otherNetworks: b["obssAirTimeFraction"].double ?? 0,
                           interference: b["edccaAirTimeFraction"].double ?? 0)
    }

    static func status(_ s: JSONValue) -> RouterStatus {
        RouterStatus(
            identity: identity(s["deviceInfo"], state: s["deviceState"]),
            wanIPv4: s["ipv4WanAddress"].string ?? "", publicIPv4: s["publicIpv4"].string ?? "",
            ipv6: s["ipv6WanAddresses"].array.compactMap { $0.string },
            internetPingMs: s["pingLatencyMs"].double, dishPingMs: s["dishPingLatencyMs"].double,
            popPingMs: s["popPingLatencyMs"].double, popPingIPv6Ms: s["popIpv6PingLatencyMs"].double,
            pingDropRate: s["pingDropRate"].double ?? 0, pingDropRate5m: s["pingDropRate5m"].double ?? 0,
            popPingDropRate5m: s["popPingDropRate5m"].double ?? 0,
            alerts: alertNames(s["alerts"]), dishId: s["dishId"].string ?? "",
            dishDisablement: s["dishDisablementCode"].string ?? "",
            softwareUpdateState: s["softwareUpdateStats"]["state"].string ?? "",
            airtime2: airtime(s["rf2GhzStatus"]), airtime5: airtime(s["rf5GhzStatus"]),
            clientCount: s["clients"].array.filter { ($0["role"].string ?? "CLIENT") == "CLIENT" }.count,
            noWanLink: s["noWanLink"].bool ?? false)
    }

    static func band(_ s: String?) -> RadioBand {
        switch s {
        case "RF_2GHZ": .ghz2
        case "RF_5GHZ": .ghz5
        case "RF_5GHZ_HIGH": .ghz5High
        case "ETH": .ethernet
        default: .unknown
        }
    }

    static func link(_ l: JSONValue, throughput: String = "throughputMbpsLast15sAvg") -> LinkStats {
        LinkStats(rateMbps: l["rateMbps"].double ?? 0, throughputMbps: max(0, l[throughput].double ?? 0),
                  mcs: l["mcs"].int ?? 0, nss: l["nss"].int ?? 0, widthMHz: l["bandwidth"].int ?? 0)
    }

    static func client(_ c: JSONValue) -> NetworkClient {
        NetworkClient(
            id: UInt32(truncatingIfNeeded: c["clientId"].int ?? 0), name: c["name"].string ?? "",
            givenName: c["givenName"].string ?? "", mac: c["macAddress"].string ?? "", ip: c["ipAddress"].string ?? "",
            band: band(c["iface"].string), role: c["role"].string ?? "CLIENT", rssi: c["signalStrength"].double,
            snr: c["snr"].double, channelWidthMHz: c["channelWidth"].int ?? 0,
            rx: link(c["rxStats"]), tx: link(c["txStats"]), associatedSeconds: c["associatedTimeS"].int ?? 0,
            upstreamMac: c["upstreamMacAddress"].string ?? "", hops: c["hopsFromController"].int ?? 0,
            wifiMode: c["modeStr"].string ?? "", downloadMB: c["downloadMb"].int ?? 0, uploadMB: c["uploadMb"].int ?? 0)
    }

    static func clients(_ r: JSONValue) -> [NetworkClient] { r["clients"].array.map(client) }

    static func radio(_ r: JSONValue) -> [RadioStat] {
        r["radioStats"].array.map { s in
            let rssi = ["rssi1", "rssi2", "rssi3", "rssi4"].compactMap { s["antennaStatus"][$0].double }
            return RadioStat(
                band: band(s["band"].string),
                rxPackets: UInt64(max(0, s["rxStats"]["packets"].double ?? 0)),
                rxFrameErrors: UInt64(max(0, s["rxStats"]["frameErrors"].double ?? 0)),
                txPackets: UInt64(max(0, s["txStats"]["packets"].double ?? 0)),
                temperatureC: s["thermalStatus"]["temp2"].double, dutyCycle: s["thermalStatus"]["dutyCycle"].double,
                rssi: rssi)
        }
    }

    static func event(_ e: JSONValue) -> DeviceEvent {
        DeviceEvent(
            severity: e["severity"].string?.replacingOccurrences(of: "EVENT_SEVERITY_", with: "").capitalized ?? "",
            reason: e["reason"].string ?? "",
            start: Date(timeIntervalSince1970: (e["startTimestampNs"].double ?? 0) / 1e9),
            duration: (e["durationNs"].double ?? 0) / 1e9)
    }
}
