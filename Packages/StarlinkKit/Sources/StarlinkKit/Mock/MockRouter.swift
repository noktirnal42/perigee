import Foundation
import RouterAPI
import SwiftProtobuf

enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let d = try? Data(contentsOf: url) else { return Data("{}".utf8) }
        return d
    }
}

/// In-memory stand-in for a Starlink router. Backs SwiftUI previews, the demo mode and every write-path test.
/// It honours `apply_<field>` semantics like the real device: only fields whose flag is set are changed.
public final class MockRouterTransport: RouterTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var config: WifiConfig
    private var _requests: [String] = []
    private var _patches: [WifiConfig] = []
    private var _renames: [(UInt32, String)] = []
    private var tick = 0
    private let deniedMethods: Set<String>
    private let latency: Duration
    private var failNextWrite: DeviceError?
    private var clientNames: [UInt32: String] = [:]

    /// - Parameter denied: Swift method names answered with PermissionDenied, like the real LAN session does.
    public init(denied: Set<String> = ["wifiGetChannels", "wifiGetPingMetrics", "wifiGetTracerouteStatus", "wifiStartTraceroute"],
                latency: Duration = .zero) {
        self.deniedMethods = denied
        self.latency = latency
        var cfg = WifiConfig()
        if let r = try? RouterResponse(jsonUTF8Data: Fixture.data("router_wifi_config"), options: Self.opts) {
            cfg = r.wifiGetConfig.wifiConfig
        }
        self.config = cfg
    }

    static let opts: JSONDecodingOptions = { var o = JSONDecodingOptions(); o.ignoreUnknownFields = true; return o }()

    // MARK: Test inspection

    public var requestLog: [String] { lock.withLock { _requests } }
    var patches: [WifiConfig] { lock.withLock { _patches } }
    var currentConfig: WifiConfig { lock.withLock { config } }
    public var writeCount: Int { lock.withLock { _patches.count + _renames.count } }
    public func failNextWrite(with e: DeviceError) { lock.withLock { failNextWrite = e } }
    func setConfig(_ c: WifiConfig) { lock.withLock { config = c } }

    // MARK: RouterTransport

    public func handle(_ request: RouterRequest) async throws -> RouterResponse {
        if latency > .zero { try await Task.sleep(for: latency) }
        let name = MethodPolicy.caseName(of: request.request) ?? "?"
        lock.withLock { _requests.append(name) }
        if deniedMethods.contains(name) { throw DeviceError.permissionDenied(method: name) }
        return try lock.withLock { try respond(to: request, name: name) }
    }

    private func fixture(_ n: String) throws -> RouterResponse {
        try RouterResponse(jsonUTF8Data: Fixture.data(n), options: Self.opts)
    }

    private func respond(to request: RouterRequest, name: String) throws -> RouterResponse {
        tick += 1
        let t = Double(tick)
        switch request.request {
        case .getStatus:
            var r = try fixture("router_status")
            r.wifiGetStatus.pingLatencyMs = Float(29 + 4 * sin(t / 3) + (tick % 7 == 0 ? 18 : 0))
            r.wifiGetStatus.popPingLatencyMs = Float(26 + 3 * sin(t / 4))
            r.wifiGetStatus.dishPingLatencyMs = 0.6
            r.wifiGetStatus.config = config
            return r
        case .wifiGetClients:
            var r = try fixture("router_clients")
            for i in r.wifiGetClients.clients.indices {
                if let n = clientNames[r.wifiGetClients.clients[i].clientID] { r.wifiGetClients.clients[i].givenName = n }
                r.wifiGetClients.clients[i].rxStats.throughputMbpsLast15SAvg *= Float(1 + 0.4 * sin(t / 2 + Double(i)))
            }
            return r
        case .getRadioStats:
            var r = try fixture("router_radio_stats")
            for i in r.getRadioStats.radioStats.indices {
                r.getRadioStats.radioStats[i].rxStats.packets += UInt64(tick * 900)
            }
            return r
        case .wifiGetConfig:
            var r = RouterResponse()
            r.wifiGetConfig.wifiConfig = config
            return r
        case .getHistory:
            return Self.syntheticHistory(seed: tick)
        case .getSpeedtestStatus:
            return RouterResponse()
        case .wifiGetClientHistory:
            var r = RouterResponse()
            let n = 120
            r.wifiGetClientHistory.current = UInt64(n)
            r.wifiGetClientHistory.rxThroughputMbps = (0..<n).map { Float(8 + 6 * sin(Double($0) / 7)) }
            r.wifiGetClientHistory.txThroughputMbps = (0..<n).map { Float(1 + sin(Double($0) / 9)) }
            r.wifiGetClientHistory.rxRateMbps = (0..<n).map { _ in 866 }
            return r
        case .wifiSetConfig:
            if let e = failNextWrite { failNextWrite = nil; throw e }
            let patch = request.wifiSetConfig.wifiConfig
            _patches.append(patch)
            Self.apply(patch: patch, to: &config)
            var r = RouterResponse()
            r.wifiSetConfig.updatedWifiConfig = config
            return r
        case .wifiSetClientGivenName:
            let c = request.wifiSetClientGivenName.clientConfig
            _renames.append((c.clientID, c.givenName))
            clientNames[c.clientID] = c.givenName
            return RouterResponse()
        case .reboot, .startSpeedtest, .getDeviceInfo, .getLog:
            return RouterResponse()
        default:
            throw DeviceError.unimplemented(method: name)
        }
    }

    /// Mirrors the device's semantic: copy a field only when its `apply_` flag is set.
    static func apply(patch p: WifiConfig, to c: inout WifiConfig) {
        if p.applyChannel2Ghz { c.channel2Ghz = p.channel2Ghz }
        if p.applyChannel5Ghz { c.channel5Ghz = p.channel5Ghz }
        if p.applyChannel5GhzHigh { c.channel5GhzHigh = p.channel5GhzHigh }
        if p.applyHtBandwidth2Ghz { c.htBandwidth2Ghz = p.htBandwidth2Ghz }
        if p.applyHtBandwidth5Ghz { c.htBandwidth5Ghz = p.htBandwidth5Ghz }
        if p.applyHtBandwidth5GhzHigh { c.htBandwidth5GhzHigh = p.htBandwidth5GhzHigh }
        if p.applyVhtBandwidth { c.vhtBandwidth = p.vhtBandwidth }
        if p.applyVhtBandwidth5GhzHigh { c.vhtBandwidth5GhzHigh = p.vhtBandwidth5GhzHigh }
        if p.applyWirelessMode2Ghz { c.wirelessMode2Ghz = p.wirelessMode2Ghz }
        if p.applyWirelessMode5Ghz { c.wirelessMode5Ghz = p.wirelessMode5Ghz }
        if p.applyWirelessMode5GhzHigh { c.wirelessMode5GhzHigh = p.wirelessMode5GhzHigh }
        if p.applyTxPowerLevel2Ghz { c.txPowerLevel2Ghz = p.txPowerLevel2Ghz }
        if p.applyTxPowerLevel5Ghz { c.txPowerLevel5Ghz = p.txPowerLevel5Ghz }
        if p.applyTxPowerLevel5GhzHigh { c.txPowerLevel5GhzHigh = p.txPowerLevel5GhzHigh }
        if p.applyDfsEnabled { c.dfsEnabled = p.dfsEnabled }
        if p.applyDisableBandSteering { c.disableBandSteering = p.disableBandSteering }
        if p.applyDisable2Ghz { c.disable2Ghz = p.disable2Ghz }
        if p.applyDisable5Ghz { c.disable5Ghz = p.disable5Ghz }
        if p.applyDisable5GhzHigh { c.disable5GhzHigh = p.disable5GhzHigh }
        if p.applyBypassMode { c.bypassMode = p.bypassMode }
        if p.applySecureDns { c.secureDns = p.secureDns }
        if p.applyNameservers { c.nameservers = p.nameservers }
        if p.applyOutdoorMode { c.outdoorMode = p.outdoorMode }
        if p.applyCustomPowerTable { c.customPowerTable = p.customPowerTable }
        if p.applyWanHostDscpMark { c.wanHostDscpMark = p.wanHostDscpMark }
        if p.applyWanTrafficControl { c.wanTrafficControl = p.wanTrafficControl }
        if p.applyNetworks { c.networks = p.networks }
    }

    /// 3 minutes of plausible WAN latency with an occasional spike, shaped like the real ring buffer.
    static func syntheticHistory(seed: Int) -> RouterResponse {
        var r = RouterResponse()
        let n = 900
        r.wifiGetHistory.current = UInt64(n + 400)  // wrapped ring, exercises the unwrapping path
        var lat = [Float](repeating: 0, count: n), drop = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let idx = (n + 400 + i) % n
            let base = 28 + 4 * sin(Double(i) / 25) + Double((i * 7919) % 5)
            let spike = (i % 97 == 0) ? 60.0 : 0
            lat[idx] = Float(base + spike)
            drop[idx] = (i % 211 == 0) ? 1 : 0
        }
        r.wifiGetHistory.pingLatencyMs = lat
        r.wifiGetHistory.pingDropRate = drop
        return r
    }
}
