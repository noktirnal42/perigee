import Foundation
import Testing
@testable import StarlinkKit

@Suite("Automation engine")
struct AutomationTests {
    private func tempEngine() -> AutomationEngine {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeAutomationTests-\(UUID().uuidString)", isDirectory: true)
        return AutomationEngine(directory: dir)
    }

    @Test("A breach only fires once it has been sustained")
    func sustainedBeforeFiring() async {
        let engine = tempEngine()
        let rule = AlertRule(metric: .ping, condition: .above, threshold: 100, sustainedFor: 30)
        await engine.setRules([rule])
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let fired1 = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0)
        #expect(fired1.isEmpty)   // just breached, not sustained yet

        let fired2 = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(15))
        #expect(fired2.isEmpty)   // still within the sustain window

        let fired3 = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(31))
        #expect(fired3.count == 1)
        #expect(fired3[0].ruleId == rule.id)
    }

    @Test("A fired rule does not re-fire until the breach clears")
    func cooldownUntilCleared() async {
        let engine = tempEngine()
        let rule = AlertRule(metric: .ping, condition: .above, threshold: 100, sustainedFor: 10)
        await engine.setRules([rule])
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        _ = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0)
        let fired = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(11))
        #expect(fired.count == 1)

        // Still breached: no second notification for the same ongoing problem.
        let stillFiring = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(20))
        #expect(stillFiring.isEmpty)

        // Clears, then breaches again: should fire again after another sustained window.
        _ = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 20), now: t0.addingTimeInterval(25))
        _ = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(30))
        let refired = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: true, internetPingMs: 150), now: t0.addingTimeInterval(41))
        #expect(refired.count == 1)

        let history = await engine.fired
        #expect(history.count == 2)
    }

    @Test("Reachability rules fire from the sample's reachable flags, not a threshold field")
    func reachabilityRules() async throws {
        let engine = tempEngine()
        let rule = AlertRule(metric: .dishOffline, condition: .above, threshold: 0.5, sustainedFor: 5)
        await engine.setRules([rule])
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let first = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: false), now: t0)
        #expect(first.isEmpty)   // breach just started, not sustained yet
        let fired = await engine.evaluate(.init(date: t0, routerReachable: true, dishReachable: false), now: t0.addingTimeInterval(6))
        try #require(fired.count == 1)
        #expect(fired[0].title == "Dish went offline")
    }

    @Test("Disabled rules never fire")
    func disabledRulesDoNotFire() async {
        let engine = tempEngine()
        let rule = AlertRule(metric: .ping, condition: .above, threshold: 10, sustainedFor: 0, enabled: false)
        await engine.setRules([rule])
        let fired = await engine.evaluate(.init(date: .now, routerReachable: true, dishReachable: true, internetPingMs: 999), now: .now)
        #expect(fired.isEmpty)
    }

    @Test("Rules and fired history persist across engine instances")
    func persistsAcrossInstances() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeAutomationTests-\(UUID().uuidString)", isDirectory: true)
        let engine = AutomationEngine(directory: dir)
        let rule = AlertRule(metric: .ping, condition: .above, threshold: 10, sustainedFor: 0)
        await engine.setRules([rule])
        _ = await engine.evaluate(.init(date: .now, routerReachable: true, dishReachable: true, internetPingMs: 999), now: .now)

        let reopened = AutomationEngine(directory: dir)
        let rules = await reopened.rules
        let fired = await reopened.fired
        #expect(rules.map(\.id) == [rule.id])
        #expect(fired.count == 1)
    }

    @Test("A fresh engine ships with a sensible default rule set")
    func defaultsAreSensible() async {
        let engine = tempEngine()
        let rules = await engine.rules
        #expect(!rules.isEmpty)
        #expect(rules.contains { $0.metric == .routerOffline })
        #expect(rules.contains { $0.metric == .dishOffline })
    }
}

@Suite("Weekly recap")
struct WeeklyRecapTests {
    @Test("Summarizes uptime and average ping from history")
    func computesFromHistory() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeRecapTests-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(directory: dir)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.debugSetClock(base)
        await store.record(.init(date: base, routerReachable: true, dishReachable: true, internetPingMs: 20))
        await store.record(.init(date: base.addingTimeInterval(60), routerReachable: true, dishReachable: true, internetPingMs: 30))
        await store.flush()

        let recap = await WeeklyRecap.compute(from: store, now: base.addingTimeInterval(120))
        #expect(recap != nil)
        #expect(recap?.uptimeFraction == 1.0)
        #expect(recap?.avgPingMs != nil)
        #expect(recap!.summary.contains("uptime"))
    }

    @Test("Returns nil when there is no history yet")
    func nilWithNoHistory() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeRecapTests-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(directory: dir)
        let recap = await WeeklyRecap.compute(from: store)
        #expect(recap == nil)
    }
}
