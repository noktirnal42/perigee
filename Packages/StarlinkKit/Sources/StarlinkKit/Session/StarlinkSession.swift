import Foundation
import Observation

public enum DataSource: String, Sendable, Codable { case live, demo }

public enum LinkState: Sendable, Equatable {
    case connecting
    case online
    case degraded(String)      // reachable but something's off (WAN down, dish unreachable...)
    case offline(OfflineReason)
}

public enum OfflineReason: Sendable, Equatable {
    case notOnStarlinkNetwork
    case localNetworkDenied
    public var title: String {
        switch self { case .notOnStarlinkNetwork: "Devices unavailable"; case .localNetworkDenied: "Local network access needed" }
    }
    public var advice: String {
        switch self {
        case .notOnStarlinkNetwork:
            "Check your network connection and device addresses, then refresh."
        case .localNetworkDenied:
            "Allow “Local Network” access for Perigee in system settings. Without it the system blocks connections to your router."
        }
    }
}

public struct ChangeRecord: Sendable, Identifiable, Equatable {
    public enum Revert: Sendable, Equatable { case wifi(WifiSetting), dish(DishSetting) }
    public let id = UUID()
    public var date: Date
    public var title: String
    public var from: String
    public var to: String
    public var verified: Bool
    public var revert: Revert
    public var applied: Revert
    public var revertedAt: Date?

    /// False when the previous value can't be written back exactly (e.g. an unset traffic-control mode).
    public var canRevert: Bool {
        if case .wifi(let s) = revert { return s.canRestore }
        return true
    }
}

/// The app's single source of truth: owns both device services, polls them, and exposes everything the UI shows.
@MainActor @Observable
public final class StarlinkSession {
    // Configuration
    public var routerHost = "192.168.1.1"
    public var dishHost = "192.168.100.1"
    public private(set) var source: DataSource = .live

    /// Writes are OFF every launch; flipping this is the only way any `set_*` call can pass the guard.
    public var writesEnabled = false { didSet { gate.writesEnabled = writesEnabled } }

    // Live data
    public private(set) var link: LinkState = .connecting
    public private(set) var routerStatus: RouterStatus?
    public private(set) var dishStatus: DishStatus?
    public private(set) var clients: [NetworkClient] = []
    public private(set) var radios: [RadioStat] = []
    public private(set) var tuning: WifiTuning?
    public private(set) var routerHistory: HistorySeries?
    public private(set) var dishHistory: DishHistory?
    public private(set) var obstruction: ObstructionMap?
    public private(set) var dishSettings: DishSettings?
    public private(set) var capabilities: [Capability] = []
    public private(set) var recentPing: [Double] = []
    public private(set) var changeLog: [ChangeRecord] = []
    public private(set) var lastUpdated: Date?
    public private(set) var routerReachable = false
    public private(set) var dishReachable = false
    public private(set) var lastError: String?
    /// Set when a device answered a configuration change with PermissionDenied. Settings then become view-only until reconnect.
    public private(set) var routerWritesRefused = false
    public private(set) var dishWritesRefused = false

    public let gate = WriteGate()
    public let results: ResultsStore
    public private(set) var history: HistoryStore

    private var router: RouterService?
    private var dish: DishService?
    private var pollTask: Task<Void, Never>?
    private var tickCount = 0
    private let injectedSource: DataSource?
    private let injectedHistory: HistoryStore?
    private let demoRefusesWrites: Bool

    /// - Parameter demoRefusesWrites: Demo mode only: behave like a router that answers every change with PermissionDenied
    ///   (what real Starlink routers do over the LAN), so that state can be previewed and tested.
    /// - Parameter history: Pass a specific store (e.g. for tests); otherwise one is chosen based on `source`.
    public init(source: DataSource = .live, results: ResultsStore = ResultsStore(), demoRefusesWrites: Bool = false,
                history: HistoryStore? = nil) {
        self.results = results
        self.injectedSource = source
        self.source = source
        self.demoRefusesWrites = demoRefusesWrites
        self.injectedHistory = history
        self.history = history ?? HistoryStore.makeDefault(for: source)
        build()
        if demoRefusesWrites && source == .demo { routerWritesRefused = true }
    }

    // MARK: Lifecycle

    private func build() {
        switch source {
        case .demo:
            var denied: Set<String> = ["wifiGetChannels", "wifiGetPingMetrics", "wifiGetTracerouteStatus", "wifiStartTraceroute"]
            if demoRefusesWrites { denied.formUnion(["wifiSetConfig", "wifiSetClientGivenName"]) }
            router = RouterService(transport: GuardedRouterTransport(base: MockRouterTransport(denied: denied, latency: .milliseconds(120)), gate: gate),
                                   sleep: { _ in })
            dish = DishService(transport: GuardedDishTransport(base: MockDishTransport(), gate: gate))
        case .live:
            do {
                router = RouterService(transport: GuardedRouterTransport(base: try GRPCRouterTransport(host: routerHost), gate: gate))
                dish = DishService(transport: GuardedDishTransport(base: try GRPCDishTransport(host: dishHost), gate: gate))
            } catch {
                router = nil; dish = nil
                lastError = "Couldn't set up the connection: \(error.localizedDescription)"
            }
        }
    }

    public func setSource(_ s: DataSource) {
        guard s != source else { return }
        stop()
        source = s
        reset()
        if injectedHistory == nil { history = HistoryStore.makeDefault(for: s) }
        build()
        start()
    }

    public func reconnect() {
        stop(); reset(); build(); start()
    }

    private func reset() {
        link = .connecting; routerStatus = nil; dishStatus = nil; clients = []; radios = []; tuning = nil
        routerHistory = nil; dishHistory = nil; obstruction = nil; dishSettings = nil; capabilities = []
        recentPing = []; routerReachable = false; dishReachable = false; tickCount = 0
        routerWritesRefused = false; dishWritesRefused = false
        changeLog = []; lastError = nil; lastUpdated = nil; writesEnabled = false
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    public func stop() { pollTask?.cancel(); pollTask = nil }

    public func refreshNow() async { await tick(force: true) }

    // MARK: Polling

    private func tick(force: Bool = false) async {
        guard let router, let dish else { link = .offline(.notOnStarlinkNetwork); return }
        let n = tickCount
        tickCount += 1
        let heavy = force || n % 4 == 0        // every ~12 s
        let first = n == 0 || force

        async let rs = capture { try await router.status() }
        async let ds = capture { try await dish.status() }
        let (routerResult, dishResult) = await (rs, ds)

        switch routerResult {
        case .success(let s):
            routerStatus = s; routerReachable = true
            if let p = s.internetPingMs { recentPing.append(p); if recentPing.count > 90 { recentPing.removeFirst(recentPing.count - 90) } }
        case .failure: routerReachable = false
        }
        switch dishResult {
        case .success(let s): dishStatus = s; dishReachable = true
        case .failure: dishReachable = false
        }
        updateLink(routerError: routerResult.failureValue, dishError: dishResult.failureValue)

        if routerReachable {
            if let c = await capture({ try await router.clients() }).successValue { clients = c }
            if heavy || first {
                if let r = await capture({ try await router.radioStats() }).successValue { radios = r }
                if let h = await capture({ try await router.history() }).successValue { routerHistory = h }
                if tuning == nil || force, let t = await capture({ try await router.wifiTuning() }).successValue { tuning = t }
            }
        }
        if dishReachable, heavy || first {
            if let h = await capture({ try await dish.history() }).successValue { dishHistory = h }
            if dishSettings == nil || force, let s = await capture({ try await dish.settings() }).successValue { dishSettings = s }
            if obstruction == nil || force, let m = await capture({ try await dish.obstructionMap() }).successValue { obstruction = m }
        }
        if first, routerReachable || dishReachable {
            let rc = await router.probeCapabilities()
            let dc = await dish.probeCapabilities()
            capabilities = rc + dc
        }
        if routerReachable || dishReachable { lastUpdated = Date() }

        await history.record(HistorySample(
            routerReachable: routerReachable, dishReachable: dishReachable,
            internetPingMs: routerStatus?.internetPingMs, pingDropRate: routerStatus?.pingDropRate,
            obstructionFraction: dishStatus?.obstructionFraction,
            frameErrorRate5: radios.first(where: { $0.band == .ghz5 })?.frameErrorRate,
            frameErrorRate2: radios.first(where: { $0.band == .ghz2 })?.frameErrorRate,
            clientCount: routerReachable ? clients.count : nil
        ))
    }

    private func updateLink(routerError: DeviceError?, dishError: DeviceError?) {
        switch (routerReachable, dishReachable) {
        case (false, false):
            link = .offline(.notOnStarlinkNetwork)
            if let e = routerError ?? dishError { lastError = e.localizedDescription }
        case (true, _):
            lastError = nil
            if routerStatus?.noWanLink == true { link = .degraded("Router has no WAN link") }
            else if !dishReachable { link = .degraded("Dish isn't answering") }
            else if !(routerStatus?.alerts.isEmpty ?? true) { link = .degraded("Router reports an alert") }
            else { link = .online }
        case (false, true):
            link = .degraded("Router isn't answering")
        }
    }

    private func capture<T: Sendable>(_ op: @Sendable () async throws -> T) async -> Result<T, DeviceError> {
        do { return .success(try await op()) }
        catch { return .failure(DeviceError.map(error, method: "")) }
    }

    // MARK: Derived

    public var ssid: String? { tuning?.networks.first(where: { !$0.isGuest })?.ssid }
    public var wirelessClients: [NetworkClient] { clients.filter { !$0.isController } }
    public var pingSuccess: Double? { routerHistory.flatMap { Advisor.successRate(dropRate: Array($0.dropRate.suffix(900))) } }
    public var jitter: Double? { routerHistory.flatMap { Advisor.latencyStats(Array($0.latencyMs.suffix(900))).jitter } }
    public var medianLatency: Double? { routerHistory.flatMap { Advisor.latencyStats(Array($0.latencyMs.suffix(900))).median } }

    public func capability(_ method: String) -> Capability? { capabilities.first { $0.method == method } }
    public func isDenied(_ method: String) -> Bool { capability(method)?.state == .denied }

    // MARK: Writes

    public func apply(_ setting: WifiSetting, expected: WifiSetting? = nil) async throws -> ChangeRecord {
        guard let router else { throw DeviceError.unreachable("Not connected.") }
        let r: WifiChangeResult
        do { r = try await router.apply(setting, expected: expected) }
        catch let e as DeviceError where e.isWriteRefusal {
            routerWritesRefused = true; syncCapabilityStates()
            await history.addAnnotation(.init(kind: .writeRefused, title: "\(setting.title) refused", detail: e.localizedDescription))
            throw e
        }
        tuning = r.tuning
        let rec = ChangeRecord(date: r.date, title: setting.title, from: r.previous.displayValue, to: setting.displayValue,
                               verified: r.verified, revert: .wifi(r.previous), applied: .wifi(r.applied))
        changeLog.insert(rec, at: 0)
        await history.addAnnotation(.init(kind: .tuningChange, title: rec.title, detail: "\(rec.from) → \(rec.to)"))
        return rec
    }

    public func apply(_ setting: DishSetting) async throws -> ChangeRecord {
        guard let dish else { throw DeviceError.unreachable("Not connected.") }
        let r: DishChangeResult
        do { r = try await dish.apply(setting) }
        catch let e as DeviceError where e.isWriteRefusal {
            dishWritesRefused = true; syncCapabilityStates()
            await history.addAnnotation(.init(kind: .writeRefused, title: "\(setting.title) refused", detail: e.localizedDescription))
            throw e
        }
        dishSettings = r.settings
        let rec = ChangeRecord(date: Date(), title: setting.title, from: r.previous.displayValue, to: setting.displayValue,
                               verified: r.verified, revert: .dish(r.previous), applied: .dish(setting))
        changeLog.insert(rec, at: 0)
        await history.addAnnotation(.init(kind: .dishChange, title: rec.title, detail: "\(rec.from) → \(rec.to)"))
        return rec
    }

    @discardableResult
    public func revert(_ record: ChangeRecord) async throws -> ChangeRecord {
        let result: ChangeRecord
        switch (record.revert, record.applied) {
        case (.wifi(let previous), .wifi(let applied)):
            result = try await apply(previous, expected: applied)
        case (.dish(let previous), .dish):
            result = try await apply(previous)
        default:
            throw WifiSettingError.invalid("The saved change cannot be reverted.")
        }
        if result.verified, let i = changeLog.firstIndex(where: { $0.id == record.id }) {
            changeLog[i].revertedAt = Date()
        }
        return result
    }

    /// Lets the user try again after a refusal (e.g. after the firmware or their account situation changed).
    public func clearWriteRefusals() { routerWritesRefused = false; dishWritesRefused = false }

    private func syncCapabilityStates() {
        capabilities = capabilities.map { c in
            var c = c
            let book = c.device == .router ? router?.capabilities : dish?.capabilities
            if let s = book?.state(c.method), s != .unknown { c.state = s }
            return c
        }
    }

    public func rename(_ client: NetworkClient, to name: String) async throws {
        guard let router else { throw DeviceError.unreachable("Not connected.") }
        do { try await router.rename(client: client, to: name) }
        catch let e as DeviceError where e.isWriteRefusal { routerWritesRefused = true; syncCapabilityStates(); throw e }
        if let c = await capture({ try await router.clients() }).successValue { clients = c }
    }

    public func revealPassword(network: WifiNetworkInfo) async throws -> String? {
        guard let router else { return nil }
        return try await router.password(network: network.networkIndex, bss: network.bssIndex)
    }

    public func rebootRouter() async throws {
        guard let router else { return }
        try await DestructiveConfirmation.run { try await router.reboot() }
    }

    public func setDishStowed(_ stowed: Bool) async throws {
        guard let dish else { return }
        try await DestructiveConfirmation.run { try await dish.setStowed(stowed) }
    }

    // MARK: Diagnostics passthroughs

    public func syslog() async throws -> String {
        guard let router else { throw DeviceError.unreachable("Not connected.") }
        return try await router.syslog()
    }
    public func clientHistory(_ c: NetworkClient) async throws -> ClientHistory {
        guard let router else { throw DeviceError.unreachable("Not connected.") }
        return try await router.clientHistory(clientId: c.id)
    }
    public func speedtest() async throws -> SpeedtestState {
        guard let router else { throw DeviceError.unreachable("Not connected.") }
        return try await router.speedtestStatus()
    }

    public var settingsSummary: StallResult.SettingsSnapshot? {
        guard let t = tuning else { return nil }
        let ch = t.channel5 == 0 ? "auto" : "\(t.channel5)"
        return .init(summary: "5 GHz ch \(ch) · \(t.vht5.label) · DFS \(t.dfsEnabled ? "on" : "off") · \(t.traffic.label)")
    }
}

private extension Result {
    var successValue: Success? { if case .success(let v) = self { v } else { nil } }
    var failureValue: Failure? { if case .failure(let e) = self { e } else { nil } }
}
