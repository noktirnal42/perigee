import Foundation
import Testing
@testable import StarlinkKit

@Suite("Decoding & mapping")
struct MappingTests {
    func service() -> (RouterService, MockRouterTransport) {
        let m = MockRouterTransport()
        return (RouterService(transport: GuardedRouterTransport(base: m, gate: WriteGate()), sleep: { _ in }), m)
    }

    @Test func status() async throws {
        let (svc, _) = service()
        let s = try await svc.status()
        #expect(s.identity.hardwareVersion == "v2")
        #expect(s.identity.countryCode == "US")
        #expect(s.internetPingMs != nil)
        #expect(s.clientCount >= 5)
        #expect(s.publicIPv4 == "203.0.113.42")
    }

    @Test func clients() async throws {
        let (svc, _) = service()
        let cs = try await svc.clients()
        let mac = try #require(cs.first(where: { $0.name == "Studio-Mac" }))
        #expect(mac.band == .ghz5)
        #expect(mac.rx.rateMbps == 866)
        #expect(mac.channelWidthMHz == 80)
        #expect(cs.contains(where: { $0.band == .ghz2 }))
        #expect(cs.first(where: { $0.isController })?.band == .ethernet)
    }

    @Test func radioHealth() async throws {
        let (svc, _) = service()
        let radios = try await svc.radioStats()
        let five = try #require(radios.first(where: { $0.band == .ghz5 }))
        #expect(five.frameErrorRate > 0 && five.frameErrorRate < 0.1)
        #expect(five.rssi.count == 3)   // 4th antenna reports NaN
        #expect(five.temperatureC == 42)
    }

    @Test func tuningAndPasswordsNeverInSnapshot() async throws {
        let (svc, _) = service()
        let t = try await svc.wifiTuning()
        #expect(t.channel5 == 0 && t.channel2 == 0)
        #expect(t.networks.count == 2)
        #expect(t.networks.allSatisfy { $0.hasPassword && $0.ssid == "Perigee_Demo" })
        if case .ackSuppression = t.traffic {} else { Issue.record("fixture has ack suppression") }
        let encoded = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        #expect(!encoded.contains("demo-password-123"), "WifiTuning must never carry passwords")
        let pw = try await svc.password(network: 0, bss: 0)
        #expect(pw == "demo-password-123")
    }

    @Test func historyRingUnwrapsOldestToNewest() {
        // ring of 5, 7 samples ever written: slots hold [5,6,2,3,4] → oldest..newest = 2,3,4,5,6
        let out = RouterService.ordered([5, 6, 2, 3, 4], current: 7)
        #expect(out.compactMap { $0 } == [2, 3, 4, 5, 6])
        #expect(RouterService.ordered([1, 2, 0, 0, 0], current: 2).compactMap { $0 } == [1, 2])
        #expect(RouterService.ordered([.nan, -1, 4], current: 3).compactMap { $0 } == [4])
    }

    @Test func dish() async throws {
        let svc = DishService(transport: GuardedDishTransport(base: MockDishTransport(), gate: WriteGate()))
        let s = try await svc.status()
        #expect(s.tiltDeg != nil)
        #expect(s.hardwareHealthy)
        let map = try await svc.obstructionMap()
        #expect(map.rows == 123 && map.snr.count == 123 * 123)
        let h = try await svc.history()
        #expect(h.latencyMs.count == 900)
    }

    @Test func vendors() {
        #expect(MACVendor.describe("c2:5a:11:00:00:01") == "Private address")
        #expect(MACVendor.describe("74:24:9f:aa:bb:cc") == "Starlink")
        #expect(MACVendor.describe("garbage") == "Unknown vendor")
    }
}

@Suite("Stall analysis")
struct StallAnalysisTests {
    @Test("Matches ab.sh on a synthetic run: one 1.2 s stall every 3 s")
    func cadence() {
        var rtt = [Double?](repeating: 3, count: 150)
        for start in stride(from: 15, to: 150, by: 15) { for i in start..<min(start + 6, 150) { rtt[i] = i % 2 == 0 ? nil : 400 } }
        let r = StallAnalysis.analyze(rtt: rtt, target: "192.168.1.1", label: "t")
        #expect(r.episodes == 9)
        #expect(abs((r.averageGapSeconds ?? 0) - 3.0) < 0.001)
        #expect(r.lossPercent > 10)
        #expect(r.verdict.grade == .bad)
    }

    @Test func cleanRun() {
        let r = StallAnalysis.analyze(rtt: (0..<150).map { _ in 2.5 }, target: "x", label: "clean")
        #expect(r.episodes == 0 && r.lossPercent == 0 && r.averageGapSeconds == nil)
        #expect(r.medianMs == 2.5 && r.p95Ms == 2.5)
        #expect(r.verdict.grade == .great)
    }

    @Test func nearbyBadSamplesMergeIntoOneEpisode() {
        var rtt = [Double?](repeating: 3, count: 50)
        rtt[10] = 50; rtt[14] = nil; rtt[20] = 99   // 0.8 s apart → merged; 1.2 s later → new
        #expect(StallAnalysis.analyze(rtt: rtt, target: "x", label: "x").episodes == 2)
    }

    @Test func resultsPersist() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ResultsStore(directory: dir)
        await store.add(StallAnalysis.analyze(rtt: [1, 2, nil], target: "x", label: "one"))
        let reopened = ResultsStore(directory: dir)
        #expect(await reopened.results.count == 1)
        #expect(await reopened.results.first?.label == "one")
    }
    @Test func corruptHistoryIsNotOverwritten() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("stall-results.json")
        let original = Data("not valid json".utf8)
        try original.write(to: file)
        let store = ResultsStore(directory: dir)
        #expect(await store.persistenceError != nil)
        await store.add(StallAnalysis.analyze(rtt: [1], target: "x", label: "new"))
        #expect(try Data(contentsOf: file) == original)
        #expect(await store.persistenceError != nil)
    }

}
