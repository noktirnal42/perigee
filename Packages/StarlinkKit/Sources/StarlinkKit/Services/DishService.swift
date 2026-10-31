import Foundation
import DishAPI

public struct DishChangeResult: Sendable, Equatable {
    public var applied: DishSetting
    public var previous: DishSetting
    public var verified: Bool
    public var settings: DishSettings
}

public actor DishService {
    private let transport: any DishTransport
    public nonisolated let capabilities: CapabilityBook

    public init(transport: any DishTransport, capabilities: CapabilityBook = CapabilityBook()) {
        self.transport = transport; self.capabilities = capabilities
    }

    private func send(_ method: String, _ build: (inout DishRequest) -> Void) async throws -> DishResponse {
        var r = DishRequest()
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

    // MARK: Reads

    public func status() async throws -> DishStatus {
        let r = try await send("get_status") { $0.getStatus = .init() }
        let data: Data
        do { data = try r.dishGetStatus.jsonUTF8Data() } catch { throw DeviceError.malformedResponse("\(error)") }
        return DishMapper.status(JSONValue(data: data))
    }

    public func settings() async throws -> DishSettings {
        let r = try await send("dish_get_config") { $0.dishGetConfig = .init() }
        return DishMapper.settings(r.dishGetConfig.dishConfig)
    }

    public func obstructionMap() async throws -> ObstructionMap {
        let r = try await send("dish_get_obstruction_map") { $0.dishGetObstructionMap = .init() }
        let m = r.dishGetObstructionMap
        return ObstructionMap(rows: Int(m.numRows), cols: Int(m.numCols), snr: m.snr,
                              minElevationDeg: Double(m.minElevationDeg), maxThetaDeg: Double(m.maxThetaDeg))
    }

    public func history() async throws -> DishHistory {
        let r = try await send("get_history") { $0.getHistory = .init() }
        let h = r.dishGetHistory
        func ord(_ a: [Float]) -> [Double?] { RouterService.ordered(a, current: h.current) }
        let outages = h.outages.map { o in
            DeviceEvent(severity: "Outage", reason: "\(o.cause)", start: Date(timeIntervalSince1970: Double(o.startTimestampNs) / 1e9),
                        duration: Double(o.durationNs) / 1e9)
        }
        return DishHistory(latencyMs: ord(h.popPingLatencyMs), dropRate: ord(h.popPingDropRate),
                           downlinkBps: ord(h.downlinkThroughputBps).map { $0 ?? 0 },
                           uplinkBps: ord(h.uplinkThroughputBps).map { $0 ?? 0 }, outages: outages)
    }

    public func probeCapabilities() async -> [Capability] {
        _ = try? await status(); _ = try? await settings(); _ = try? await obstructionMap(); _ = try? await history()
        return KnownCapabilities.dish.map { var c = $0; c.state = capabilities.state(c.method); return c }
    }

    // MARK: Writes

    /// Sets exactly one dish setting (plus its `apply_` flag) and re-reads to verify.
    public func apply(_ setting: DishSetting) async throws -> DishChangeResult {
        let before = try await settings()
        let previous = setting.value(in: before)
        let cfg = try DishMapper.config(for: setting)
        _ = try await send("dish_set_config") { $0.dishSetConfig.dishConfig = cfg }
        let after = try await settings()
        return DishChangeResult(applied: setting, previous: previous, verified: setting.value(in: after) == setting, settings: after)
    }

    /// Destructive: only succeeds inside `DestructiveConfirmation.run`.
    public func setStowed(_ stowed: Bool) async throws {
        _ = try await send("dish_stow") { $0.dishStow.unstow = !stowed }
    }
}

enum DishMapper {
    static func settings(_ c: SpaceX_API_Device_DishConfig) -> DishSettings {
        DishSettings(snowMelt: SnowMeltMode(rawValue: c.snowMeltMode.rawValue) ?? .auto,
                     levelDish: DishLevelMode(rawValue: c.levelDishMode.rawValue) ?? .tiltNormally,
                     powerSave: c.powerSaveMode, powerSaveStartMinutes: Int(c.powerSaveStartMinutes),
                     powerSaveDurationMinutes: Int(c.powerSaveDurationMinutes),
                     threeDayDeferral: c.swupdateThreeDayDeferralEnabled, updateRebootHour: Int(c.swupdateRebootHour))
    }

    static func config(for s: DishSetting) throws -> SpaceX_API_Device_DishConfig {
        var c = SpaceX_API_Device_DishConfig()
        switch s {
        case .snowMelt(let m): c.snowMeltMode = .init(rawValue: m.rawValue) ?? .auto; c.applySnowMeltMode = true
        case .levelDish(let m): c.levelDishMode = .init(rawValue: m.rawValue) ?? .tiltLikeNormal; c.applyLevelDishMode = true
        case .powerSave(let on): c.powerSaveMode = on; c.applyPowerSaveMode = true
        case .powerSaveWindow(let start, let dur):
            guard (0..<1440).contains(start), (0...1440).contains(dur) else { throw WifiSettingError.invalid("Sleep window must fit within a day.") }
            c.powerSaveStartMinutes = UInt32(start); c.applyPowerSaveStartMinutes = true
            c.powerSaveDurationMinutes = UInt32(dur); c.applyPowerSaveDurationMinutes = true
        case .threeDayDeferral(let on): c.swupdateThreeDayDeferralEnabled = on; c.applySwupdateThreeDayDeferralEnabled = true
        case .updateRebootHour(let h):
            guard (0..<24).contains(h) else { throw WifiSettingError.invalid("Hour must be 0–23.") }
            c.swupdateRebootHour = UInt32(h); c.applySwupdateRebootHour = true
        }
        return c
    }

    static func status(_ s: JSONValue) -> DishStatus {
        let a = s["alignmentStats"]
        let alerts = RouterMapper.alertNames(s["alerts"])
        let obstruction = s["obstructionStats"]
        let fraction = obstruction["fractionObstructed"].double
        let ready = s["readyStates"]
        let healthy = ["cady", "scp", "l1l2", "xphy", "aap", "rf"].allSatisfy { ready[$0].bool ?? true }
        return DishStatus(
            identity: RouterMapper.identity(s["deviceInfo"], state: s["deviceState"]),
            popPingMs: s["popPingLatencyMs"].double, popPingDropRate: s["popPingDropRate"].double,
            downlinkBps: s["downlinkThroughputBps"].double ?? 0, uplinkBps: s["uplinkThroughputBps"].double ?? 0,
            obstructionFraction: fraction ?? 0, obstructionValidSeconds: obstruction["validS"].double ?? 0,
            azimuthDeg: s["boresightAzimuthDeg"].double, elevationDeg: s["boresightElevationDeg"].double,
            tiltDeg: a["tiltAngleDeg"].double, alerts: alerts,
            softwareUpdateState: s["softwareUpdateState"].string ?? "", disablementCode: s["disablementCode"].string ?? "",
            snowMeltActive: s["config"]["snowMeltMode"].string == "ALWAYS_ON",
            ethSpeedMbps: s["ethSpeedMbps"].int ?? 0, mobility: s["mobilityClass"].string ?? "",
            classOfService: s["classOfService"].string ?? "",
            hasActuators: (s["hasActuators"].string ?? "") == "HAS_ACTUATORS_YES",
            stowRequested: s["stowRequested"].bool ?? false,
            dlRestricted: s["dlBandwidthRestrictedReason"].string ?? "", ulRestricted: s["ulBandwidthRestrictedReason"].string ?? "",
            signalAboveNoise: s["isSnrAboveNoiseFloor"].bool ?? true,
            gpsLocked: !(s["gpsStats"]["noSatsAfterTtff"].bool ?? false),
            hardwareHealthy: healthy)
    }
}
