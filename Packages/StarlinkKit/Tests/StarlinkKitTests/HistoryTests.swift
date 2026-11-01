import Foundation
import Testing
@testable import StarlinkKit

@Suite("History store")
struct HistoryTests {
    private func tempStore(retention: HistoryStore.Retention = .init()) -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeHistoryTests-\(UUID().uuidString)", isDirectory: true)
        return (HistoryStore(directory: dir, retention: retention), dir)
    }

    @Test("Samples in the same minute aggregate into one bucket")
    func aggregatesWithinAMinute() async throws {
        let (store, _) = tempStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.debugSetClock(base)   // keeps retention/compaction from folding this fixed-in-the-past bucket away
        await store.record(.init(date: base, routerReachable: true, dishReachable: true, internetPingMs: 20, pingDropRate: 0))
        await store.record(.init(date: base.addingTimeInterval(10), routerReachable: true, dishReachable: true, internetPingMs: 30, pingDropRate: 0))
        await store.record(.init(date: base.addingTimeInterval(20), routerReachable: true, dishReachable: false, internetPingMs: 40, pingDropRate: 0.1))
        // A sample in the next minute forces the first minute's bucket to finalize.
        await store.record(.init(date: base.addingTimeInterval(60), routerReachable: true, dishReachable: true, internetPingMs: 99))

        // -120s, not -10s: a minute bucket's `start` is floored to :00, which can be up to 59s before `base`.
        let buckets = await store.buckets(resolution: .minute, since: base.addingTimeInterval(-120))
        try #require(buckets.count == 1)
        let b = buckets[0]
        #expect(b.sampleCount == 3)
        #expect(b.avgPingMs == 30)
        #expect(b.minPingMs == 20)
        #expect(b.maxPingMs == 40)
        #expect(abs(b.uptimeFraction - (2.0 / 3.0)) < 0.0001)
    }

    @Test("Old minute buckets fold into an hour bucket once retention passes")
    func foldsMinutesIntoHour() async {
        let (store, _) = tempStore(retention: .init(minuteHours: 1, hourDays: 90))
        let base = Date(timeIntervalSince1970: 1_700_000_000)  // not near an hour boundary
        await store.debugSetClock(base)
        await store.record(.init(date: base, routerReachable: true, dishReachable: true, internetPingMs: 20))
        await store.record(.init(date: base.addingTimeInterval(60), routerReachable: true, dishReachable: true, internetPingMs: 22))
        var minutes = await store.buckets(resolution: .minute, since: base.addingTimeInterval(-3600))
        #expect(minutes.count == 1)   // the second sample's minute is still pending, not yet finalized

        await store.debugSetClock(base.addingTimeInterval(2 * 3600))
        await store.record(.init(date: base.addingTimeInterval(120), routerReachable: true, dishReachable: true, internetPingMs: 24))

        minutes = await store.buckets(resolution: .minute, since: base.addingTimeInterval(-3600))
        let hours = await store.buckets(resolution: .hour, since: base.addingTimeInterval(-3600))
        #expect(minutes.isEmpty)
        #expect(hours.count == 1)
        #expect(hours[0].sampleCount == 2)
        #expect(hours[0].avgPingMs == 21)
    }

    @Test("Annotations are kept newest-first and filtered by date")
    func annotationsOrderAndFilter() async {
        let (store, _) = tempStore()
        let now = Date()
        await store.addAnnotation(.init(date: now.addingTimeInterval(-120), kind: .tuningChange, title: "old"))
        await store.addAnnotation(.init(date: now, kind: .stallTest, title: "new"))
        let all = await store.annotations(since: now.addingTimeInterval(-3600))
        #expect(all.map(\.title) == ["new", "old"])
        let recentOnly = await store.annotations(since: now.addingTimeInterval(-60))
        #expect(recentOnly.map(\.title) == ["new"])
    }

    @Test("uptimeFraction weights by sample count")
    func uptimeFractionWeighted() async {
        let (store, _) = tempStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.debugSetClock(base)
        for i in 0..<3 { await store.record(.init(date: base.addingTimeInterval(Double(i) * 10), routerReachable: true, dishReachable: true)) }
        await store.record(.init(date: base.addingTimeInterval(70), routerReachable: false, dishReachable: false))
        await store.flush()
        let frac = await store.uptimeFraction(since: base.addingTimeInterval(-120))
        #expect(frac != nil)
        #expect(abs((frac ?? -1) - 0.75) < 0.0001)
    }

    @Test("History persists across store instances pointed at the same directory")
    func persistsAcrossInstances() async throws {
        let (store, dir) = tempStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.debugSetClock(base)
        await store.record(.init(date: base, routerReachable: true, dishReachable: true, internetPingMs: 15))
        await store.flush()

        let reopened = HistoryStore(directory: dir)
        let buckets = await reopened.buckets(resolution: .minute, since: base.addingTimeInterval(-120))
        try #require(buckets.count == 1)
        #expect(buckets[0].avgPingMs == 15)
    }

    @Test("A corrupted history file is left untouched rather than silently wiped")
    func toleratesCorruptFile() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let minuteURL = dir.appendingPathComponent("history-minute.json")
        try! Data("not json".utf8).write(to: minuteURL)

        let store = HistoryStore(directory: dir)
        let errorBefore = await store.persistenceError
        #expect(errorBefore != nil)

        await store.record(.init(date: Date(), routerReachable: true, dishReachable: true))
        await store.flush()
        // Persistence is blocked after a load failure, so the corrupt file must be exactly as it was.
        let contents = try! String(contentsOf: minuteURL, encoding: .utf8)
        #expect(contents == "not json")
    }
}
