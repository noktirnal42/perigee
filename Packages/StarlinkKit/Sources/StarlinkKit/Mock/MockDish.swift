import Foundation
import DishAPI
import SwiftProtobuf

public final class MockDishTransport: DishTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var config: SpaceX_API_Device_DishConfig
    private var _requests: [String] = []
    private var _patches: [SpaceX_API_Device_DishConfig] = []
    private var tick = 0

    public init() {
        var c = SpaceX_API_Device_DishConfig()
        if let r = try? DishResponse(jsonUTF8Data: Fixture.data("dish_config"), options: MockRouterTransport.opts) {
            c = r.dishGetConfig.dishConfig
        }
        config = c
    }

    public var requestLog: [String] { lock.withLock { _requests } }
    var patches: [SpaceX_API_Device_DishConfig] { lock.withLock { _patches } }

    public func handle(_ request: DishRequest) async throws -> DishResponse {
        let name = MethodPolicy.caseName(of: request.request) ?? "?"
        return try lock.withLock {
            _requests.append(name); tick += 1
            switch request.request {
            case .getStatus:
                var r = try DishResponse(jsonUTF8Data: Fixture.data("dish_status"), options: MockRouterTransport.opts)
                r.dishGetStatus.popPingLatencyMs = Float(24 + 3 * sin(Double(tick) / 3))
                r.dishGetStatus.downlinkThroughputBps = Float(8e6 + 5e6 * sin(Double(tick) / 2))
                r.dishGetStatus.uplinkThroughputBps = Float(1.2e6 + 5e5 * sin(Double(tick) / 4))
                return r
            case .dishGetConfig:
                var r = DishResponse(); r.dishGetConfig.dishConfig = config; return r
            case .dishSetConfig:
                let p = request.dishSetConfig.dishConfig
                _patches.append(p)
                if p.applySnowMeltMode { config.snowMeltMode = p.snowMeltMode }
                if p.applyLevelDishMode { config.levelDishMode = p.levelDishMode }
                if p.applyPowerSaveMode { config.powerSaveMode = p.powerSaveMode }
                if p.applyPowerSaveStartMinutes { config.powerSaveStartMinutes = p.powerSaveStartMinutes }
                if p.applyPowerSaveDurationMinutes { config.powerSaveDurationMinutes = p.powerSaveDurationMinutes }
                if p.applySwupdateThreeDayDeferralEnabled { config.swupdateThreeDayDeferralEnabled = p.swupdateThreeDayDeferralEnabled }
                if p.applySwupdateRebootHour { config.swupdateRebootHour = p.swupdateRebootHour }
                return DishResponse()
            case .dishGetObstructionMap:
                return Self.syntheticObstructionMap()
            case .getHistory:
                var r = DishResponse()
                let n = 900
                r.dishGetHistory.current = UInt64(n)
                r.dishGetHistory.popPingLatencyMs = (0..<n).map { Float(24 + 3 * sin(Double($0) / 30) + Double(($0 * 31) % 4)) }
                r.dishGetHistory.popPingDropRate = (0..<n).map { $0 % 300 == 0 ? 0.4 : 0 }
                r.dishGetHistory.downlinkThroughputBps = (0..<n).map { Float(6e6 + 4e6 * sin(Double($0) / 20)) }
                r.dishGetHistory.uplinkThroughputBps = (0..<n).map { Float(8e5 + 3e5 * sin(Double($0) / 15)) }
                return r
            case .dishStow:
                return DishResponse()
            default:
                throw DeviceError.unimplemented(method: name)
            }
        }
    }

    /// A 123×123 sky view: clear overhead, with a tree-line wedge in the north-east and a roof edge to the south.
    static func syntheticObstructionMap() -> DishResponse {
        var r = DishResponse()
        let n = 123
        r.dishGetObstructionMap.numRows = UInt32(n); r.dishGetObstructionMap.numCols = UInt32(n)
        r.dishGetObstructionMap.minElevationDeg = 25; r.dishGetObstructionMap.maxThetaDeg = 65
        var snr = [Float](repeating: -1, count: n * n)
        let c = Double(n - 1) / 2
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = c - Double(y)
            let rad = (dx * dx + dy * dy).squareRoot()
            guard rad < c else { continue }
            let az = atan2(dx, dy) * 180 / .pi           // 0 = north
            var v: Float = Float(0.85 + 0.12 * sin(Double(x * y) * 0.05))
            if (30...75).contains(az), rad > c * 0.45 { v = 0 }          // trees
            if abs(az) > 150, rad > c * 0.7 { v = 0 }                    // roof edge
            if v > 0 && Int.random(in: 0..<40) == 0 { v = -1 }          // unobserved speckle
            snr[y * n + x] = v
        } }
        r.dishGetObstructionMap.snr = snr
        return r
    }
}
