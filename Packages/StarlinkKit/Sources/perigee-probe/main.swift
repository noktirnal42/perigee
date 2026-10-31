import Foundation
import StarlinkKit

// Read-only live check: decodes every read endpoint the app uses. Never writes; the WriteGate stays closed.
let gate = WriteGate(writesEnabled: false)
if CommandLine.arguments.contains("ping") {
    let host = CommandLine.arguments.last == "ping" ? "192.168.1.1" : CommandLine.arguments.last!
    let rtt = try await ICMPPinger().run(host: host, count: 50, interval: 0.2) { _ in }
    let r = StallAnalysis.analyze(rtt: rtt, target: host, label: "probe")
    print(String(format: "ping %@: loss %.1f%% median %.1fms p95 %.1fms max %.1fms episodes %d gap %@", host, r.lossPercent, r.medianMs, r.p95Ms, r.maxMs, r.episodes, r.averageGapSeconds.map { String(format: "%.1fs", $0) } ?? "n/a"))
    exit(0)
}
do {
    let router = RouterService(transport: GuardedRouterTransport(base: try GRPCRouterTransport(), gate: gate))
    let dish = DishService(transport: GuardedDishTransport(base: try GRPCDishTransport(), gate: gate))

    func step<T>(_ name: String, _ body: () async throws -> T, show: (T) -> String) async {
        do { print("✓ \(name): \(show(try await body()))") }
        catch { print("✗ \(name): \(error.localizedDescription)") }
    }
    await step("router.status", { try await router.status() }) {
        "up \(Int($0.identity.uptime))s, ping \($0.internetPingMs ?? -1)ms, dish \($0.dishPingMs ?? -1)ms, clients \($0.clientCount), alerts \($0.alerts), air5 busy \($0.airtime5?.busy ?? -1), obss \($0.airtime5?.otherNetworks ?? -1)"
    }
    await step("router.clients", { try await router.clients() }) { cs in
        cs.map { "\($0.displayName)[\($0.band.short) \(Int($0.rssi ?? 0))dBm \(Int($0.rx.rateMbps))Mbps]" }.joined(separator: ", ")
    }
    await step("router.radio", { try await router.radioStats() }) {
        $0.map { "\($0.band.label) err \(String(format: "%.2f", $0.frameErrorRate * 100))% \($0.temperatureC ?? 0)°C" }.joined(separator: "; ")
    }
    await step("router.tuning", { try await router.wifiTuning() }) {
        "ch2=\($0.channel2) ch5=\($0.channel5) vht=\($0.vht5) dfs=\($0.dfsEnabled) traffic=\($0.traffic.label) nets=\($0.networks.map { "\($0.ssid)/\($0.band.short)" })"
    }
    await step("router.history", { try await router.history() }) {
        "lat samples \($0.latencyMs.count), non-nil \($0.latencyMs.compactMap { $0 }.count), events \($0.events.map(\.title))"
    }
    await step("router.speedtest", { try await router.speedtestStatus() }) { "\($0)" }
    await step("router.traceroute", { try await router.tracerouteStatus() }) { "\($0.state) hops \($0.hops.count)" }
    await step("dish.status", { try await dish.status() }) {
        "ping \($0.popPingMs ?? -1) dl \(Int($0.downlinkBps / 1000))kbps obstructed \($0.obstructionFraction ?? -1) tilt \($0.tiltDeg ?? -1) alerts \($0.alerts) healthy \($0.hardwareHealthy)"
    }
    await step("dish.settings", { try await dish.settings() }) { "\($0)" }
    await step("dish.obstruction", { try await dish.obstructionMap() }) {
        "\($0.rows)x\($0.cols), observed \($0.snr.filter { $0 >= 0 }.count)"
    }
    await step("dish.history", { try await dish.history() }) {
        "samples \($0.latencyMs.count) non-nil \($0.latencyMs.compactMap { $0 }.count) outages \($0.outages.count)"
    }
    print("--- capabilities")
    for c in await router.probeCapabilities() { print("router \(c.method): \(c.state)") }
    for c in await dish.probeCapabilities() { print("dish   \(c.method): \(c.state)") }
    // Prove the gate: a write must be refused locally, never sent.
    do { _ = try await router.apply(.dfs(false)); print("✗ WRITE WAS NOT BLOCKED") }
    catch { print("✓ write blocked locally: \(error.localizedDescription)") }
} catch { print("setup failed: \(error)") }
