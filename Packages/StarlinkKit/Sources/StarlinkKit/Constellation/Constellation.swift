import Foundation

public struct Observer: Sendable, Equatable, Codable {
    public var latitude: Double      // degrees
    public var longitude: Double     // degrees
    public var altitudeMeters: Double
    public init(latitude: Double, longitude: Double, altitudeMeters: Double = 0) {
        self.latitude = latitude; self.longitude = longitude; self.altitudeMeters = altitudeMeters
    }
    public var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

public struct TLERecord: Sendable, Equatable {
    public var name: String
    public var noradID: Int
    public var line1: String
    public var line2: String
}

public enum TLEParser {
    /// Parses 3-line element sets (name + 2 lines). Malformed entries are skipped, never fatal.
    public static func parse(_ text: String) -> [TLERecord] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [TLERecord] = []
        var i = 0
        while i + 2 < lines.count {
            let name = lines[i], l1 = lines[i + 1], l2 = lines[i + 2]
            if l1.hasPrefix("1 "), l2.hasPrefix("2 "), l1.count >= 64, l2.count >= 64,
               let id = Int(l1.dropFirst(2).prefix(5).trimmingCharacters(in: .whitespaces)) {
                out.append(TLERecord(name: name, noradID: id, line1: l1, line2: l2)); i += 3
            } else { i += 1 }
        }
        return out
    }

    static func field(_ s: String, _ a: Int, _ b: Int) -> String {
        let chars = Array(s)
        guard a < chars.count else { return "" }
        return String(chars[a..<min(b, chars.count)]).trimmingCharacters(in: .whitespaces)
    }

    /// Implied-decimal exponent fields like " 28098-4" or "-11606-4".
    static func expField(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return 0 }
        var mant = t, exp = 0
        if let idx = t.lastIndex(where: { $0 == "-" || $0 == "+" }), idx != t.startIndex {
            mant = String(t[t.startIndex..<idx]); exp = Int(t[idx...]) ?? 0
        }
        var sign = 1.0
        if mant.hasPrefix("-") { sign = -1; mant.removeFirst() } else if mant.hasPrefix("+") { mant.removeFirst() }
        guard let m = Double("0." + mant) else { return 0 }
        return sign * m * pow(10, Double(exp))
    }

    public static func propagator(for r: TLERecord) -> SGP4Propagator? {
        let l1 = r.line1, l2 = r.line2
        guard let yy = Int(field(l1, 18, 20)), let day = Double(field(l1, 20, 32)),
              let inc = Double(field(l2, 8, 16)), let raan = Double(field(l2, 17, 25)),
              let ecc = Double("0." + field(l2, 26, 33)), let argp = Double(field(l2, 34, 42)),
              let ma = Double(field(l2, 43, 51)), let n = Double(field(l2, 52, 63)) else { return nil }
        let year = yy < 57 ? 2000 + yy : 1900 + yy
        var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let jan1 = cal.date(from: comps) else { return nil }
        let epoch = jan1.addingTimeInterval((day - 1) * 86400)
        return SGP4Propagator(epoch: epoch, inclinationDeg: inc, raanDeg: raan, eccentricity: ecc, argPerigeeDeg: argp,
                              meanAnomalyDeg: ma, meanMotionRevPerDay: n, bstar: expField(field(l1, 53, 61)))
    }
}

public struct SatelliteState: Sendable, Equatable, Identifiable {
    public var id: Int                     // NORAD id
    public var name: String
    public var latitude: Double, longitude: Double, altitudeKm: Double
    public var ecefKm: SIMD3<Float>
    public var azimuth: Double, elevation: Double, rangeKm: Double   // from the observer, degrees / km
    public var speedKmS: Double
    public var inclinationDeg: Double
}

public struct ConstellationSnapshot: Sendable {
    public var date: Date
    public var satellites: [SatelliteState]
    public var inView: [SatelliteState]            // elevation ≥ minElevation, highest first
    public var aboveHorizon: Int
    public var connected: ConnectedGuess?
}

public struct ConnectedGuess: Sendable, Equatable {
    public var satellite: SatelliteState
    /// Angle between the dish's boresight and this satellite, in degrees. Smaller = more certain.
    public var separationDeg: Double
    public var confidence: Confidence
    public enum Confidence: String, Sendable { case high, medium, low }
}

public enum Geo {
    static let a = 6378.137, f = 1 / 298.257223563
    static let e2 = f * (2 - f)

    /// Greenwich mean sidereal time (radians) for a date.
    public static func gmst(_ date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545.0) / 36525
        var s = -6.2e-6 * t * t * t + 0.093104 * t * t + (876600 * 3600 + 8640184.812866) * t + 67310.54841
        s = (s * Double.pi / 180 / 240).truncatingRemainder(dividingBy: 2 * .pi)
        return s < 0 ? s + 2 * .pi : s
    }

    public static func ecef(of o: Observer) -> SIMD3<Double> {
        let lat = o.latitude * .pi / 180, lon = o.longitude * .pi / 180, h = o.altitudeMeters / 1000
        let n = a / (1 - e2 * sin(lat) * sin(lat)).squareRoot()
        return SIMD3((n + h) * cos(lat) * cos(lon), (n + h) * cos(lat) * sin(lon), (n * (1 - e2) + h) * sin(lat))
    }

    /// Azimuth (° clockwise from north), elevation (°) and range (km) of an ECEF point seen from `o`.
    public static func lookAngles(from o: Observer, to p: SIMD3<Double>) -> (az: Double, el: Double, range: Double) {
        let lat = o.latitude * .pi / 180, lon = o.longitude * .pi / 180
        let d = p - ecef(of: o)
        let e = -sin(lon) * d.x + cos(lon) * d.y
        let n = -sin(lat) * cos(lon) * d.x - sin(lat) * sin(lon) * d.y + cos(lat) * d.z
        let u = cos(lat) * cos(lon) * d.x + cos(lat) * sin(lon) * d.y + sin(lat) * d.z
        let range = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        var az = atan2(e, n) * 180 / .pi
        if az < 0 { az += 360 }
        return (az, asin(max(-1, min(1, u / range))) * 180 / .pi, range)
    }

    /// Angle (°) between two sky directions.
    public static func separation(az1: Double, el1: Double, az2: Double, el2: Double) -> Double {
        let r = Double.pi / 180
        let c = sin(el1 * r) * sin(el2 * r) + cos(el1 * r) * cos(el2 * r) * cos((az1 - az2) * r)
        return acos(max(-1, min(1, c))) * 180 / .pi
    }
}

/// The Starlink shell as seen from one place on Earth at one instant. Built from public orbital elements (CelesTrak).
public final class Constellation: @unchecked Sendable {
    struct Entry { let record: TLERecord; let prop: SGP4Propagator }
    let entries: [Entry]
    public var count: Int { entries.count }
    public let elementsDate: Date?    // newest element-set epoch

    public init(records: [TLERecord]) {
        var e: [Entry] = []
        e.reserveCapacity(records.count)
        for r in records { if let p = TLEParser.propagator(for: r) { e.append(Entry(record: r, prop: p)) } }
        entries = e
        elementsDate = e.map(\.prop.epoch).max()
    }

    public convenience init(tle text: String) { self.init(records: TLEParser.parse(text)) }

    /// Minimum elevation at which the dish can use a satellite.
    public static let minElevation = 25.0

    public func snapshot(at date: Date, observer: Observer?, boresight: (az: Double, el: Double)? = nil) -> ConstellationSnapshot {
        let gst = Geo.gmst(date)
        let cg = cos(gst), sg = sin(gst)
        var states: [SatelliteState] = []
        states.reserveCapacity(entries.count)
        for en in entries {
            let minutes = date.timeIntervalSince(en.prop.epoch) / 60
            guard let (r, v) = en.prop.propagate(minutes: minutes) else { continue }
            // TEME → ECEF by rotating through GMST (polar motion & equation of equinoxes neglected: < 1 km)
            let ecef = SIMD3(r.x * cg + r.y * sg, -r.x * sg + r.y * cg, r.z)
            let rad = (ecef.x * ecef.x + ecef.y * ecef.y + ecef.z * ecef.z).squareRoot()
            let lat = asin(ecef.z / rad) * 180 / .pi
            let lon = atan2(ecef.y, ecef.x) * 180 / .pi
            var look = (az: 0.0, el: -90.0, range: 0.0)
            if let o = observer { look = Geo.lookAngles(from: o, to: ecef) }
            let speed = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            states.append(SatelliteState(
                id: en.record.noradID, name: en.record.name, latitude: lat, longitude: lon, altitudeKm: rad - 6371.0,
                ecefKm: SIMD3<Float>(Float(ecef.x), Float(ecef.y), Float(ecef.z)),
                azimuth: look.az, elevation: look.el, rangeKm: look.range, speedKmS: speed, inclinationDeg: en.prop.inclinationDeg))
        }
        guard observer != nil else {
            return ConstellationSnapshot(date: date, satellites: states, inView: [], aboveHorizon: 0, connected: nil)
        }
        let above = states.filter { $0.elevation > 0 }
        let inView = above.filter { $0.elevation >= Self.minElevation }.sorted { $0.elevation > $1.elevation }
        var guess: ConnectedGuess?
        if let b = boresight {
            let best = above.map { ($0, Geo.separation(az1: $0.azimuth, el1: $0.elevation, az2: b.az, el2: b.el)) }.min { $0.1 < $1.1 }
            if let (s, sep) = best, sep < 8 {
                guess = ConnectedGuess(satellite: s, separationDeg: sep, confidence: sep < 1.5 ? .high : sep < 4 ? .medium : .low)
            }
        }
        return ConstellationSnapshot(date: date, satellites: states, inView: inView, aboveHorizon: above.count, connected: guess)
    }

    /// Seconds until a satellite drops below `minElevation` for this observer (nil if it is already below or the pass is > 15 min).
    public func secondsUntilLeavesView(noradID: Int, observer: Observer, from date: Date) -> Double? {
        guard let en = entries.first(where: { $0.record.noradID == noradID }) else { return nil }
        var t = 0.0
        while t <= 900 {
            let d = date.addingTimeInterval(t)
            guard let (r, _) = en.prop.propagate(minutes: d.timeIntervalSince(en.prop.epoch) / 60) else { return nil }
            let g = Geo.gmst(d)
            let ecef = SIMD3(r.x * cos(g) + r.y * sin(g), -r.x * sin(g) + r.y * cos(g), r.z)
            if Geo.lookAngles(from: observer, to: ecef).el < Self.minElevation { return t == 0 ? nil : t }
            t += 5
        }
        return nil
    }

    /// Sky track (azimuth, elevation) of one satellite from `start - before` to `start + after`, for drawing a trail.
    public func track(noradID: Int, observer: Observer, around start: Date, before: TimeInterval, after: TimeInterval, step: TimeInterval = 10) -> [(az: Double, el: Double, date: Date)] {
        guard let en = entries.first(where: { $0.record.noradID == noradID }) else { return [] }
        var out: [(Double, Double, Date)] = []
        var t = -before
        while t <= after {
            let d = start.addingTimeInterval(t)
            if let (r, _) = en.prop.propagate(minutes: d.timeIntervalSince(en.prop.epoch) / 60) {
                let g = Geo.gmst(d)
                let ecef = SIMD3(r.x * cos(g) + r.y * sin(g), -r.x * sin(g) + r.y * cos(g), r.z)
                let la = Geo.lookAngles(from: observer, to: ecef)
                if la.el > -5 { out.append((la.az, la.el, d)) }
            }
            t += step
        }
        return out
    }
}
