import Foundation
import Testing
@testable import StarlinkKit

@Suite("Risk forecast")
struct ForecastTests {
    // MARK: Satellite-density threshold logic (pure, decoupled from real orbit propagation)

    @Test("A contiguous dip below 70% of the mean becomes one window")
    func detectsADip() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let step: TimeInterval = 600
        // 10, 10, 2, 2, 10, 10 -> mean 7.33, threshold ~5.1: samples 2 and 3 dip, one contiguous window.
        let counts = [10, 10, 2, 2, 10, 10]
        let samples = counts.enumerated().map { (i, c) in (date: base.addingTimeInterval(Double(i) * step), count: c) }
        let windows = Forecast.windows(fromDensitySamples: samples, step: step)
        #expect(windows.count == 1)
        #expect(windows[0].start == base.addingTimeInterval(2 * step))
        #expect(windows[0].end == base.addingTimeInterval(4 * step))
    }

    @Test("Two separate dips become two windows")
    func detectsTwoDips() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let step: TimeInterval = 600
        let counts = [10, 1, 10, 10, 1, 10]
        let samples = counts.enumerated().map { (i, c) in (date: base.addingTimeInterval(Double(i) * step), count: c) }
        let windows = Forecast.windows(fromDensitySamples: samples, step: step)
        #expect(windows.count == 2)
    }

    @Test("A dip that runs to the end of the series is still closed off")
    func dipAtEndIsClosed() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let step: TimeInterval = 600
        let counts = [10, 10, 10, 1, 1]
        let samples = counts.enumerated().map { (i, c) in (date: base.addingTimeInterval(Double(i) * step), count: c) }
        let windows = Forecast.windows(fromDensitySamples: samples, step: step)
        #expect(windows.count == 1)
        #expect(windows[0].end == base.addingTimeInterval(5 * step))   // last sample's date + one step
    }

    @Test("A flat series with no dip produces no windows")
    func flatSeriesProducesNoWindows() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<6).map { (date: base.addingTimeInterval(Double($0) * 600), count: 8) }
        #expect(Forecast.windows(fromDensitySamples: samples, step: 600).isEmpty)
    }

    @Test("Too few samples or an all-zero series produce no windows, not a crash")
    func degenerateSeriesAreSafe() {
        #expect(Forecast.windows(fromDensitySamples: [(date: .now, count: 5), (date: .now, count: 3)], step: 600).isEmpty)
        let zeros = (0..<5).map { (date: Date.now.addingTimeInterval(Double($0) * 600), count: 0) }
        #expect(Forecast.windows(fromDensitySamples: zeros, step: 600).isEmpty)
    }

    // MARK: Satellite density against real orbital data (structural sanity only — can't control real geometry)

    @Test("Satellite-density windows against real orbit data are well-formed if any are found")
    func satelliteDensityAgainstRealData() throws {
        let url = try #require(Bundle.module.url(forResource: "starlink-snapshot", withExtension: "tle", subdirectory: "Orbits"))
        let c = Constellation(tle: try String(contentsOf: url, encoding: .utf8))
        let when = try #require(c.elementsDate)
        let windows = Forecast.satelliteDensityWindows(constellation: c, observer: Observer(latitude: 40, longitude: -105), from: when)
        for w in windows {
            #expect(w.end > w.start)
            #expect(!w.reasons.isEmpty)
        }
    }

    // MARK: Historical-hour pattern

    private func bucket(hour: Int, day: Int, obstruction: Double, uptime: Double = 1.0, samples: Int = 20) -> HistoryBucket {
        var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = day; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let start = cal.date(from: comps)!
        return HistoryBucket(start: start, resolution: .hour, sampleCount: samples, uptimeFraction: uptime, avgObstruction: obstruction)
    }

    @Test("An hour with much higher obstruction than the rest of the day is flagged")
    func flagsAnObviouslyWorseHour() {
        var buckets: [HistoryBucket] = []
        for day in 1...3 {
            for hour in 0..<24 {
                buckets.append(bucket(hour: hour, day: day, obstruction: hour == 18 ? 0.05 : 0.001))
            }
        }
        let risky = Forecast.historicalRiskHours(buckets: buckets)
        #expect(risky.contains(18))
        #expect(!risky.contains(3))
    }

    @Test("A uniform day flags nothing")
    func uniformDayFlagsNothing() {
        var buckets: [HistoryBucket] = []
        for day in 1...2 { for hour in 0..<24 { buckets.append(bucket(hour: hour, day: day, obstruction: 0.001)) } }
        #expect(Forecast.historicalRiskHours(buckets: buckets).isEmpty)
    }

    @Test("Fewer than a day's worth of buckets is treated as not enough data")
    func notEnoughDataIsIgnored() {
        let buckets = (0..<5).map { bucket(hour: $0, day: 1, obstruction: $0 == 2 ? 0.1 : 0.001) }
        #expect(Forecast.historicalRiskHours(buckets: buckets).isEmpty)
    }

    // MARK: Combined windows()

    @Test("windows() combines both signals and never crashes with nil/empty inputs")
    func combinedWindowsIsSafeWithNoData() {
        let w = Forecast.windows(constellation: nil, observer: nil, historyBuckets: [])
        #expect(w.isEmpty)
    }

    @Test("windows() surfaces an upcoming historically-risky hour even with no constellation data")
    func combinedWindowsSurfacesHistoricalSignalAlone() {
        var buckets: [HistoryBucket] = []
        let now = Date()
        let calendar = Calendar.current
        let targetHour = calendar.component(.hour, from: now.addingTimeInterval(3600))
        for day in 1...3 {
            for hour in 0..<24 {
                var comps = calendar.dateComponents([.year, .month], from: now)
                comps.day = day; comps.hour = hour
                let start = calendar.date(from: comps) ?? now
                buckets.append(HistoryBucket(start: start, resolution: .hour, sampleCount: 20, uptimeFraction: 1,
                                              avgObstruction: hour == targetHour ? 0.05 : 0.001))
            }
        }
        let windows = Forecast.windows(constellation: nil, observer: nil, historyBuckets: buckets, from: now, calendar: calendar)
        #expect(windows.contains { calendar.component(.hour, from: $0.start) == targetHour })
    }
}
