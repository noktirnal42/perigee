import Foundation
import RouterAPI

public struct WifiChangeResult: Sendable, Equatable {
    public var applied: WifiSetting
    /// What the router held before the write: feeding this to `apply` again is the one-tap revert.
    public var previous: WifiSetting
    /// True when a follow-up read confirmed the router now holds the requested value.
    public var verified: Bool
    public var tuning: WifiTuning
    public var date: Date
}

/// All router conversations. Every request goes through the injected (guarded) transport.
public actor RouterService {
    private let transport: any RouterTransport
    public nonisolated let capabilities: CapabilityBook
    private var rawConfig = WifiConfig()
    private let sleep: @Sendable (Duration) async -> Void

    public init(transport: any RouterTransport, capabilities: CapabilityBook = CapabilityBook(),
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.transport = transport; self.capabilities = capabilities; self.sleep = sleep
    }

    // MARK: Plumbing

    private func send(_ method: String, _ build: (inout RouterRequest) -> Void) async throws -> RouterResponse {
        var r = RouterRequest()
        build(&r)
        do {
            let resp = try await transport.handle(r)
            capabilities.record(method, .available)
            return resp
        } catch {
            let e = DeviceError.map(error, method: method)
            capabilities.record(method, error: e)
            throw e
        }
    }

    private func json(_ build: () throws -> Data) throws -> JSONValue {
        do { return JSONValue(data: try build()) }
        catch { throw DeviceError.malformedResponse(String(describing: error)) }
    }

    // MARK: Reads

    public func status() async throws -> RouterStatus {
        let r = try await send("get_status") { $0.getStatus = .init() }
        return RouterMapper.status(try json { try r.wifiGetStatus.jsonUTF8Data() })
    }

    public func clients() async throws -> [NetworkClient] {
        let r = try await send("wifi_get_clients") { $0.wifiGetClients = .init() }
        return RouterMapper.clients(try json { try r.wifiGetClients.jsonUTF8Data() })
    }

    public func radioStats() async throws -> [RadioStat] {
        let r = try await send("get_radio_stats") { $0.getRadioStats = .init() }
        return RouterMapper.radio(try json { try r.getRadioStats.jsonUTF8Data() })
    }

    @discardableResult
    public func wifiTuning() async throws -> WifiTuning {
        let r = try await send("wifi_get_config") { $0.wifiGetConfig = .init() }
        rawConfig = r.wifiGetConfig.wifiConfig
        return WifiTuningMapper.tuning(from: rawConfig)
    }

    /// Wi-Fi password for one SSID. Re-reads the config; never cached in the UI model and never logged.
    public func password(network: Int, bss: Int) async throws -> String? {
        try await wifiTuning()
        return WifiTuningMapper.password(in: rawConfig, network: network, bss: bss)
    }

    public func history() async throws -> HistorySeries {
        let r = try await send("get_history") { $0.getHistory = .init() }
        let h = r.wifiGetHistory
        let (lat, drop) = (Self.ordered(h.pingLatencyMs, current: h.current), Self.ordered(h.pingDropRate, current: h.current))
        let events = h.eventLog.events.map { e in
            DeviceEvent(severity: "\(e.severity)".replacingOccurrences(of: "EVENT_SEVERITY_", with: "").capitalized,
                        reason: Self.reasonName(e.reason), start: Date(timeIntervalSince1970: Double(e.startTimestampNs) / 1e9),
                        duration: Double(e.durationNs) / 1e9)
        }
        return HistorySeries(latencyMs: lat, dropRate: drop, interval: 1, events: events)
    }

    static func reasonName(_ r: SpaceX_API_Device_EventReason) -> String {
        "\(r)".replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression).uppercased()
    }

    /// Unwraps a device ring buffer (`current` = total samples ever written) to oldest→newest, mapping NaN/negatives to nil.
    static func ordered(_ ring: [Float], current: UInt64) -> [Double?] {
        guard !ring.isEmpty else { return [] }
        let n = ring.count
        let total = Int(truncatingIfNeeded: current)
        let ordered: [Float]
        if total >= n {
            let start = total % n
            ordered = Array(ring[start...] + ring[..<start])
        } else {
            ordered = Array(ring[..<min(total, n)])
        }
        return ordered.map { $0.isFinite && $0 >= 0 ? Double($0) : nil }
    }

    public func clientHistory(clientId: UInt32) async throws -> ClientHistory {
        let r = try await send("wifi_get_client_history") { $0.wifiGetClientHistory.clientID = clientId }
        let h = r.wifiGetClientHistory
        func ord(_ a: [Float]) -> [Double] { Self.ordered(a, current: h.current).map { $0 ?? 0 } }
        return ClientHistory(txMbps: ord(h.txThroughputMbps), rxMbps: ord(h.rxThroughputMbps), rxRateMbps: ord(h.rxRateMbps))
    }

    public func speedtestStatus() async throws -> SpeedtestState {
        let r = try await send("get_speedtest_status") { $0.getSpeedtestStatus = .init() }
        let j = try json { try r.getSpeedtestStatus.jsonUTF8Data() }["status"]
        func mbps(_ d: JSONValue) -> Double? { (d["bps"].double ?? d["speedBps"].double ?? d["throughputBps"].double).map { $0 / 1e6 } ?? d["mbps"].double }
        return SpeedtestState(running: j["running"].bool ?? false, downMbps: mbps(j["down"]), upMbps: mbps(j["up"]))
    }

    public func startSpeedtest(seconds: Int = 10) async throws {
        _ = try await send("start_speedtest") { $0.startSpeedtest.durationS = Int32(seconds) }
    }

    public func startTraceroute(target: String) async throws {
        guard !target.isEmpty, target.count < 254 else { throw DeviceError.malformedResponse("Enter a hostname or IP address.") }
        _ = try await send("wifi_start_traceroute") { $0.wifiStartTraceroute.target = target }
    }

    public func tracerouteStatus() async throws -> TracerouteResult {
        let r = try await send("wifi_get_traceroute_status") { $0.wifiGetTracerouteStatus = .init() }
        let s = r.wifiGetTracerouteStatus.status
        let hops = s.hops.map { h in
            TracerouteHop(index: Int(h.hopNumber), address: h.ipAddress.isEmpty ? (h.timeout ? "*" : h.hostname) : h.ipAddress,
                          rttMs: h.rttMs.map(Double.init))
        }
        return TracerouteResult(state: "\(s.state)", target: s.target, hops: hops)
    }

    public func syslog() async throws -> String {
        let r = try await send("get_log") { $0.getLog = .init() }
        let l = r.getLog.current
        return l.syslog.isEmpty ? r.getLog.syslog : l.syslog
    }

    /// Runs the read-only probes so the UI can show which features this LAN session may use.
    public func probeCapabilities() async -> [Capability] {
        _ = try? await status(); _ = try? await clients(); _ = try? await wifiTuning(); _ = try? await radioStats()
        _ = try? await history()
        _ = try? await send("wifi_get_channels") { $0.wifiGetChannels = .init() }
        _ = try? await send("wifi_get_ping_metrics") { $0.wifiGetPingMetrics = .init() }
        _ = try? await speedtestStatus(); _ = try? await tracerouteStatus()
        if let first = try? await clients().first(where: { $0.isWireless }) { _ = try? await clientHistory(clientId: first.id) }
        return KnownCapabilities.router.map { var c = $0; c.state = capabilities.state(c.method); return c }
    }

    // MARK: Writes (all guarded by WriteGate in the transport)

    /// Sets exactly one setting, then re-reads to confirm. The returned `previous` is the revert target.
    public func apply(_ setting: WifiSetting) async throws -> WifiChangeResult {
        let before = try await wifiTuningRaw()
        let previous = setting.current(in: before)
        let patch = try setting.makeConfig(base: before)
        _ = try await send("wifi_set_config") { $0.wifiSetConfig.wifiConfig = patch }

        // The router may restart Wi-Fi/WAN services after a write; retry the verification read for a while.
        var verifiedTuning: WifiTuning?
        var verified = false
        for attempt in 0..<12 {
            await sleep(attempt == 0 ? .seconds(1) : .seconds(3))
            do {
                let after = try await wifiTuningRaw()
                verifiedTuning = WifiTuningMapper.tuning(from: after)
                verified = setting.current(in: after) == setting
                break
            } catch let e as DeviceError where !e.isPermissionDenied {
                continue
            }
        }
        let tuning = verifiedTuning ?? WifiTuningMapper.tuning(from: rawConfig)
        return WifiChangeResult(applied: setting, previous: Self.revertable(previous), verified: verified, tuning: tuning, date: Date())
    }

    /// "Not set" can't be written back, so the revert target for an unset traffic control is "Off".
    static func revertable(_ s: WifiSetting) -> WifiSetting {
        if case .trafficControl(.unset) = s { return .trafficControl(.none) }
        return s
    }

    private func wifiTuningRaw() async throws -> WifiConfig {
        try await wifiTuning()
        return rawConfig
    }

    public func rename(client: NetworkClient, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 63 else { throw DeviceError.malformedResponse("Names can be up to 63 characters.") }
        _ = try await send("wifi_set_client_given_name") {
            $0.wifiSetClientGivenName.clientConfig.clientID = client.id
            $0.wifiSetClientGivenName.clientConfig.macAddress = client.mac
            $0.wifiSetClientGivenName.clientConfig.givenName = trimmed
        }
    }

    /// Destructive: only succeeds inside `DestructiveConfirmation.run`.
    public func reboot() async throws {
        _ = try await send("reboot") { $0.reboot = .init() }
    }
}
