import Foundation
import Testing
@testable import StarlinkKit

@Suite("History-aware advisor")
struct AdvisorTests {
    private func bucket(hoursAgo: Double, obstruction: Double? = nil, frameErrorRate5: Double? = nil, samples: Int = 10) -> HistoryBucket {
        HistoryBucket(start: Date().addingTimeInterval(-hoursAgo * 3600), resolution: .hour, sampleCount: samples,
                      uptimeFraction: 1, avgObstruction: obstruction, avgFrameErrorRate5: frameErrorRate5)
    }

    @Test("Rising obstruction over recent history is flagged")
    func flagsRisingObstruction() {
        let buckets = [
            bucket(hoursAgo: 48, obstruction: 0.001), bucket(hoursAgo: 36, obstruction: 0.001),
            bucket(hoursAgo: 12, obstruction: 0.02), bucket(hoursAgo: 1, obstruction: 0.02),
        ]
        let recs = Advisor.historyAdvice(recentBuckets: buckets, tuning: nil)
        #expect(recs.contains { $0.title == "Obstruction has been rising" })
    }

    @Test("Rising 5 GHz frame errors suggest a channel pin")
    func flagsRisingFrameErrors() throws {
        let buckets = [
            bucket(hoursAgo: 48, frameErrorRate5: 0.001), bucket(hoursAgo: 36, frameErrorRate5: 0.001),
            bucket(hoursAgo: 12, frameErrorRate5: 0.03), bucket(hoursAgo: 1, frameErrorRate5: 0.03),
        ]
        var tuning = WifiTuning()
        tuning.channel5 = 149
        let recs = Advisor.historyAdvice(recentBuckets: buckets, tuning: tuning)
        let rec = try #require(recs.first { $0.title == "5 GHz frame errors have been climbing" })
        #expect(rec.suggestion == .channel(.ghz5, 36))   // currently on 149, so the alternative is the 36-48 block
    }

    @Test("A flat history with few buckets or no trend suggests nothing")
    func staysQuietWithoutATrend() {
        #expect(Advisor.historyAdvice(recentBuckets: [bucket(hoursAgo: 1, obstruction: 0.01)], tuning: nil).isEmpty)
        let flat = (0..<6).map { bucket(hoursAgo: Double($0) * 4, obstruction: 0.01) }
        #expect(Advisor.historyAdvice(recentBuckets: flat, tuning: nil).isEmpty)
    }
}
