import Foundation
import Testing
@testable import StarlinkKit
import RouterAPI

/// Keys present in a patch's protobuf-JSON (proto3 omits defaults, so `apply_*` flags + non-default values only).
private func keys(of config: WifiConfig) throws -> Set<String> {
    Set(JSONValue(data: try config.jsonUTF8Data()).keys.map { $0.lowercased() })
}

@Suite("Single-field writes")
struct WifiWriteTests {
    let base = MockRouterTransport().currentConfig

    @Test("Every setting emits exactly its field and its apply_ flag",
          arguments: [
            (WifiSetting.channel(.ghz5, 149), ["channel5Ghz", "applyChannel5Ghz"]),
            (.channel(.ghz2, 6), ["channel2Ghz", "applyChannel2Ghz"]),
            (.channel(.ghz5High, 100), ["channel5GhzHigh", "applyChannel5GhzHigh"]),
            (.channel(.ghz5, 0), ["applyChannel5Ghz"]),   // 0 = auto: proto3 omits the default, the flag carries the write
            (.htBandwidth(.ghz2, .mhz20), ["htBandwidth2Ghz", "applyHtBandwidth2Ghz"]),
            (.vhtBandwidth(.ghz5, .mhz80), ["vhtBandwidth", "applyVhtBandwidth"]),
            (.vhtBandwidth(.ghz5High, .mhz160), ["vhtBandwidth5GhzHigh", "applyVhtBandwidth5GhzHigh"]),
            (.wirelessMode(.ghz5, .aanacaxMixed), ["wirelessMode5Ghz", "applyWirelessMode5Ghz"]),
            (.txPower(.ghz5, .p50), ["txPowerLevel5Ghz", "applyTxPowerLevel5Ghz"]),
            (.dfs(true), ["dfsEnabled", "applyDfsEnabled"]),
            (.bandSteeringDisabled(true), ["disableBandSteering", "applyDisableBandSteering"]),
            (.bandDisabled(.ghz2, true), ["disable2Ghz", "applyDisable2Ghz"]),
            (.bypassMode(true), ["bypassMode", "applyBypassMode"]),
            (.secureDNS(true), ["secureDns", "applySecureDns"]),
            (.nameservers(["1.1.1.1", "2606:4700:4700::1111"]), ["nameservers", "applyNameservers"]),
            (.outdoorMode(true), ["outdoorMode", "applyOutdoorMode"]),
            (.customPowerTable(true), ["customPowerTable", "applyCustomPowerTable"]),
            (.dscpMark(46), ["wanHostDscpMark", "applyWanHostDscpMark"]),
            (.trafficControl(.cake(CakeParams(bandwidth: 90))), ["wanCakeRateLimit", "applyWanTrafficControl"]),
            (.trafficControl(.none), ["wanNoTrafficControl", "applyWanTrafficControl"]),
          ])
    func oneFieldOneFlag(setting: WifiSetting, expected: [String]) throws {
        let patch = try setting.makeConfig(base: base)
        #expect(try keys(of: patch) == Set(expected.map { $0.lowercased() }), "\(setting.title)")
    }

    @Test("Hidden SSID resends networks only")
    func hiddenSSID() throws {
        let patch = try WifiSetting.hiddenSSID(true).makeConfig(base: base)
        #expect(try keys(of: patch) == ["networks", "applynetworks"])
        #expect(patch.networks.first?.basicServiceSets.allSatisfy(\.hidden) == true)
        // original passwords are carried through untouched
        #expect(patch.networks.first?.basicServiceSets.first?.authWpa2Wpa3.password == base.networks.first?.basicServiceSets.first?.authWpa2Wpa3.password)
    }

    @Test("Invalid input is rejected before anything is built")
    func validation() {
        #expect(throws: WifiSettingError.self) { try WifiSetting.nameservers(["not-an-ip"]).makeConfig(base: base) }
        #expect(throws: WifiSettingError.self) { try WifiSetting.dscpMark(99).makeConfig(base: base) }
        #expect(throws: WifiSettingError.self) { try WifiSetting.channel(.ghz5, 9999).makeConfig(base: base) }
        #expect(throws: WifiSettingError.self) { try WifiSetting.vhtBandwidth(.ghz2, .mhz80).makeConfig(base: base) }
        #expect(throws: WifiSettingError.self) { try WifiSetting.trafficControl(.cake(.init(bandwidth: 0))).makeConfig(base: base) }
        #expect(throws: WifiSettingError.self) { try WifiSetting.trafficControl(.unset).makeConfig(base: base) }
    }

    @Test("Apply writes one patch, verifies, and returns a working revert")
    func applyAndRevert() async throws {
        let mock = MockRouterTransport()
        let gate = WriteGate(writesEnabled: true)
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: gate), sleep: { _ in })

        let result = try await svc.apply(.channel(.ghz5, 149))
        #expect(result.verified)
        #expect(result.previous == .channel(.ghz5, 0))
        #expect(mock.patches.count == 1)
        #expect(mock.currentConfig.channel5Ghz == 149)
        #expect(mock.currentConfig.channel2Ghz == 0, "other fields untouched")

        let back = try await svc.apply(result.previous)
        #expect(back.verified)
        #expect(mock.currentConfig.channel5Ghz == 0)
        #expect(mock.patches.count == 2)
    }

    @Test("An unset traffic control is reported as not restorable, and writing it back is refused")
    func trafficUnsetNotRestorable() async throws {
        let mock = MockRouterTransport()
        var cfg = mock.currentConfig
        cfg.wanTrafficControl = nil
        mock.setConfig(cfg)
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        let r = try await svc.apply(.trafficControl(.cake(CakeParams(bandwidth: 100, priority: .diffserv4, ackFilter: .on))))
        #expect(r.verified)
        #expect(r.previous == .trafficControl(.unset))
        #expect(!r.previous.canRestore, "the UI must not offer a one-tap revert to an unwritable state")
        await #expect(throws: WifiSettingError.self) { _ = try await svc.apply(r.previous) }
    }

    @Test("Ack-suppression round trip keeps its parameters for revert")
    func ackRoundTrip() async throws {
        let mock = MockRouterTransport()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        let r = try await svc.apply(.trafficControl(.cake(CakeParams(bandwidth: 80))))
        guard case .trafficControl(.ackSuppression(let a)) = r.previous else { Issue.record("previous should be ack suppression"); return }
        #expect(a.cakeAckFilterAggressive)
        _ = try await svc.apply(r.previous)
        #expect(WifiTuningMapper.trafficControl(mock.currentConfig) == .ackSuppression(a))
    }

    @Test("A failed write surfaces and leaves the config alone")
    func failedWrite() async throws {
        let mock = MockRouterTransport()
        mock.failNextWrite(with: .timeout)
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        await #expect(throws: DeviceError.timeout) { _ = try await svc.apply(.dfs(true)) }
        #expect(mock.currentConfig.dfsEnabled == false)
    }

    @Test("Renaming a device sends only the client config")
    func rename() async throws {
        let mock = MockRouterTransport()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)))
        let client = try #require(try await svc.clients().first(where: { $0.name == "XBOX" }))
        try await svc.rename(client: client, to: "  Xbox Series X ")
        let after = try await svc.clients().first(where: { $0.id == client.id })
        #expect(after?.displayName == "Xbox Series X")
        #expect(mock.requestLog.filter { $0 == "wifiSetClientGivenName" }.count == 1)
    }
    @Test("A stale reviewed value cannot overwrite a newer setting")
    func staleReviewIsRejected() async throws {
        let mock = MockRouterTransport()
        var config = mock.currentConfig
        config.channel5Ghz = 44
        mock.setConfig(config)
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        await #expect(throws: WifiSettingError.self) {
            _ = try await svc.apply(.channel(.ghz5, 149), expected: .channel(.ghz5, 0))
        }
        #expect(mock.writeCount == 0)
        #expect(mock.currentConfig.channel5Ghz == 44)
    }

    @Test("A matching reviewed value permits the patch")
    func reviewedValueMatches() async throws {
        let mock = MockRouterTransport()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        let result = try await svc.apply(.channel(.ghz5, 149), expected: .channel(.ghz5, 0))
        #expect(result.verified)
        #expect(mock.writeCount == 1)
    }

    @Test("A write with unavailable read-back retains its previous value")
    func unavailableReadBackKeepsRevert() async throws {
        let mock = MockRouterTransport()
        mock.failConfigReadsAfterWrite(with: .permissionDenied(method: "wifi_get_config"))
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true)), sleep: { _ in })
        let result = try await svc.apply(.channel(.ghz5, 149), expected: .channel(.ghz5, 0))
        #expect(!result.verified)
        #expect(result.previous == .channel(.ghz5, 0))
        #expect(mock.writeCount == 1)
    }

}
