import Foundation
import Testing
@testable import StarlinkKit
import RouterAPI
import DishAPI

@Suite("Safety layer")
struct SafetyTests {
    @Test("Auth, signing, debug, test-mode and factory methods are always forbidden", arguments: Array(MethodPolicy.neverAllowed))
    func neverAllowed(name: String) {
        #expect(MethodPolicy.classify(name) == .forbidden)
        let gate = WriteGate(writesEnabled: true)
        #expect(throws: SafetyError.self) { try gate.authorize(name) }
    }

    @Test("Unknown methods default to forbidden")
    func unknown() {
        #expect(MethodPolicy.classify("somethingNewInAFutureFirmware") == .forbidden)
    }

    @Test("Reads and probes are always allowed")
    func reads() throws {
        let gate = WriteGate()
        for m in ["getStatus", "wifiGetConfig", "dishGetObstructionMap", "getRadioStats", "startSpeedtest", "wifiStartTraceroute"] {
            try gate.authorize(m)
        }
    }

    @Test("Read-only mode blocks writes before they reach the transport")
    func readOnlyBlocks() async {
        let mock = MockRouterTransport()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate()), sleep: { _ in })
        await #expect(throws: DeviceError.safety(.readOnlyMode(method: "wifiSetConfig"))) { _ = try await svc.apply(.dfs(true)) }
        try? await svc.rename(client: NetworkClient(id: 1), to: "x")
        #expect(mock.writeCount == 0)
        #expect(!mock.requestLog.contains("wifiSetConfig"))
    }

    @Test("Reboot needs writes AND an explicit confirmation")
    func rebootNeedsConfirmation() async throws {
        let mock = MockRouterTransport()
        let gate = WriteGate()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: gate), sleep: { _ in })

        await #expect(throws: DeviceError.safety(.readOnlyMode(method: "reboot"))) { try await svc.reboot() }
        gate.writesEnabled = true
        await #expect(throws: DeviceError.safety(.confirmationRequired(method: "reboot"))) { try await svc.reboot() }
        #expect(!mock.requestLog.contains("reboot"))

        try await DestructiveConfirmation.run { try await svc.reboot() }
        #expect(mock.requestLog.contains("reboot"))
    }

    @Test("Forbidden requests never leave the guard even with writes on")
    func guardBlocksForbidden() async {
        let mock = MockRouterTransport()
        let guarded = GuardedRouterTransport(base: mock, gate: WriteGate(writesEnabled: true))
        var req = RouterRequest()
        req.dishFactoryReset = .init()
        await #expect(throws: DeviceError.safety(.forbidden(method: "dishFactoryReset"))) { _ = try await guarded.handle(req) }
        var auth = RouterRequest()
        auth.authenticate = .init()
        await #expect(throws: DeviceError.self) { _ = try await guarded.handle(auth) }
        #expect(mock.requestLog.isEmpty)
    }

    @Test("Empty request is refused")
    func emptyRequest() async {
        let guarded = GuardedRouterTransport(base: MockRouterTransport(), gate: WriteGate(writesEnabled: true))
        await #expect(throws: DeviceError.safety(.emptyRequest)) { _ = try await guarded.handle(RouterRequest()) }
    }

    @Test("PermissionDenied is remembered as a capability")
    func permissionDeniedRecorded() async throws {
        let mock = MockRouterTransport()
        let svc = RouterService(transport: GuardedRouterTransport(base: mock, gate: WriteGate()), sleep: { _ in })
        let caps = await svc.probeCapabilities()
        #expect(caps.first(where: { $0.method == "wifi_get_channels" })?.state == .denied)
        #expect(caps.first(where: { $0.method == "get_status" })?.state == .available)
        #expect(caps.first(where: { $0.method == "wifi_get_traceroute_status" })?.state == .denied)
    }

    @Test("Dish writes: one field, one flag, destructive stow is gated")
    func dish() async throws {
        let mock = MockDishTransport()
        let gate = WriteGate(writesEnabled: true)
        let svc = DishService(transport: GuardedDishTransport(base: mock, gate: gate))
        let r = try await svc.apply(.snowMelt(.alwaysOn))
        #expect(r.verified)
        #expect(r.previous == .snowMelt(.alwaysOff))
        let keys = Set(JSONValue(data: try mock.patches[0].jsonUTF8Data()).keys)
        #expect(keys == ["snowMeltMode", "applySnowMeltMode"])
        _ = try await svc.apply(r.previous)
        #expect(try await svc.settings().snowMelt == .alwaysOff)

        await #expect(throws: DeviceError.safety(.confirmationRequired(method: "dishStow"))) { try await svc.setStowed(true) }
        try await DestructiveConfirmation.run { try await svc.setStowed(true) }
    }
}
