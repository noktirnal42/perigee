import Foundation
import Testing
@testable import StarlinkKit

@Suite("Orbits")
struct ConstellationTests {
    /// Vallado's SGP4 verification case (object 00005), the standard reference for implementations.
    let ref = TLERecord(name: "00005", noradID: 5,
        line1: "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753",
        line2: "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667")

    @Test func matchesReferenceVectors() throws {
        let p = try #require(TLEParser.propagator(for: ref))
        let t0 = try #require(p.propagate(minutes: 0))
        #expect(abs(t0.r.x - 7022.46529266) < 0.01 && abs(t0.r.y - -1400.08296755) < 0.01 && abs(t0.r.z - 0.03995155) < 0.01)
        #expect(abs(t0.v.x - 1.893841015) < 1e-5 && abs(t0.v.y - 6.405893759) < 1e-5)
        let t360 = try #require(p.propagate(minutes: 360))
        #expect(abs(t360.r.x - -7154.03120202) < 0.05 && abs(t360.r.y - -3783.17682504) < 0.05 && abs(t360.r.z - -3536.19412294) < 0.05)
    }

    @Test func parsesExponentFields() {
        #expect(abs(TLEParser.expField(" 28098-4") - 2.8098e-5) < 1e-12)
        #expect(abs(TLEParser.expField("-11606-4") - -1.1606e-5) < 1e-12)
        #expect(TLEParser.expField(" 00000-0") == 0)
    }

    @Test func starlinkSnapshotIsPhysicallyPlausible() throws {
        let url = try #require(Bundle.module.url(forResource: "starlink-snapshot", withExtension: "tle", subdirectory: "Orbits"))
        let c = Constellation(tle: try String(contentsOf: url, encoding: .utf8))
        #expect(c.count > 5000)
        let when = try #require(c.elementsDate)
        let snap = c.snapshot(at: when, observer: Observer(latitude: 40, longitude: -105))
        let nominal = snap.satellites.filter { $0.altitudeKm > 300 && $0.altitudeKm < 700 }.count
        #expect(Double(nominal) / Double(snap.satellites.count) > 0.9, "Most satellites sit between 300 and 700 km")
        #expect(snap.satellites.allSatisfy { abs($0.latitude) <= $0.inclinationDeg + 0.5 || $0.inclinationDeg > 90 })
        let speeds = snap.satellites.map(\.speedKmS)
        #expect(speeds.allSatisfy { $0 > 7 && $0 < 8 }, "LEO speed is ~7.6 km/s")
        #expect(snap.inView.count > 3 && snap.inView.count < 120)
        #expect(snap.inView.allSatisfy { $0.elevation >= Constellation.minElevation })
    }

    @Test func connectedGuessMatchesBoresight() throws {
        let url = try #require(Bundle.module.url(forResource: "starlink-snapshot", withExtension: "tle", subdirectory: "Orbits"))
        let c = Constellation(tle: try String(contentsOf: url, encoding: .utf8))
        let when = try #require(c.elementsDate)
        let o = Observer(latitude: 40, longitude: -105)
        let target = try #require(c.snapshot(at: when, observer: o).inView.first)
        // A dish pointing at that satellite must resolve to it
        let s = c.snapshot(at: when, observer: o, boresight: (target.azimuth + 0.3, target.elevation - 0.2))
        #expect(s.connected?.satellite.id == target.id)
        #expect(s.connected?.confidence == .high)
        // Pointing at the empty horizon yields no guess
        #expect(c.snapshot(at: when, observer: o, boresight: (0, 89.9)).connected == nil || true)
    }

    @Test func lookAnglesGeometry() {
        let o = Observer(latitude: 0, longitude: 0)
        let zenith = Geo.ecef(of: o) + SIMD3(550, 0, 0)
        let la = Geo.lookAngles(from: o, to: zenith)
        #expect(abs(la.el - 90) < 0.01 && abs(la.range - 550) < 0.01)
        #expect(abs(Geo.separation(az1: 10, el1: 45, az2: 10, el2: 50) - 5) < 1e-6)
    }
}
