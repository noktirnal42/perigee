import SwiftUI
import StarlinkKit
import CoreLocation

/// Drives the Sky screen: loads orbital data, tracks the observer's position, recomputes the constellation once a second.
@MainActor @Observable
final class SkyModel {
    var snapshot: ConstellationSnapshot?
    var observer: Observer? { didSet { persistObserver() } }
    var dataNote = "Loading satellite data…"
    var timeOffset: TimeInterval = 0          // seconds from now (time-lapse)
    var trail: [(az: Double, el: Double, date: Date)] = []
    var leavesIn: Double?
    var totalSatellites = 0
    var locationStatus: String?

    private let store = ConstellationStore()
    private var constellation: Constellation?
    private var loop: Task<Void, Never>?
    private let location = LocationProvider()

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "observer.lat") != nil {
            let o = Observer(latitude: d.double(forKey: "observer.lat"), longitude: d.double(forKey: "observer.lon"), altitudeMeters: d.double(forKey: "observer.alt"))
            if o.isValid { observer = o }
        }
    }

    private func persistObserver() {
        let d = UserDefaults.standard
        if let o = observer { d.set(o.latitude, forKey: "observer.lat"); d.set(o.longitude, forKey: "observer.lon"); d.set(o.altitudeMeters, forKey: "observer.alt") }
    }

    func start(session: StarlinkSession) {
        guard loop == nil else { return }
        if session.source == .demo, observer == nil { observer = Observer(latitude: 39.74, longitude: -104.99, altitudeMeters: 1600) }
        loop = Task { [weak self] in
            guard let self else { return }
            let c = await self.store.load(allowDownload: session.source == .live)
            self.constellation = c
            self.totalSatellites = c?.count ?? 0
            await self.refreshNote()
            while !Task.isCancelled {
                await self.recompute(session: session)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    private func refreshNote() async {
        switch await store.source {
        case .bundled: dataNote = "Bundled snapshot of orbital data (connect to the internet to refresh)."
        case .cached(let d): dataNote = "Orbital data from \(Fmt.relative(d)) (CelesTrak)."
        case .downloaded(let d): dataNote = "Orbital data refreshed \(Fmt.relative(d)) from CelesTrak."
        }
        if let e = await store.lastError { dataNote = e }
    }

    func recompute(session: StarlinkSession) async {
        guard let c = constellation else { return }
        let obs = observer
        let when = Date().addingTimeInterval(timeOffset)
        var bore: (az: Double, el: Double)?
        if session.source == .live, let az = session.dishStatus?.azimuthDeg, let el = session.dishStatus?.elevationDeg { bore = (az, el) }
        let demo = session.source == .demo
        let snap: ConstellationSnapshot = await Task.detached(priority: .userInitiated) {
            var s = c.snapshot(at: when, observer: obs, boresight: bore)
            if demo, let top = s.inView.dropFirst(2).first ?? s.inView.first {
                // Demo: pretend the dish is tracking a high satellite so the UI is populated.
                s = c.snapshot(at: when, observer: obs, boresight: (top.azimuth + 0.4, top.elevation - 0.3))
            }
            return s
        }.value
        snapshot = snap
        if let o = obs, let g = snap.connected {
            trail = c.track(noradID: g.satellite.id, observer: o, around: when, before: 90, after: 240)
            leavesIn = c.secondsUntilLeavesView(noradID: g.satellite.id, observer: o, from: when)
        } else { trail = []; leavesIn = nil }
    }

    func useCurrentLocation() {
        locationStatus = "Finding you…"
        Task {
            do {
                let loc = try await location.requestOnce()
                observer = Observer(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, altitudeMeters: max(0, loc.altitude))
                locationStatus = nil
            } catch { locationStatus = error.localizedDescription }
        }
    }
}

/// One-shot Core Location request. The coordinate never leaves the device.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }

    struct LocationError: LocalizedError { let errorDescription: String? }

    func requestOnce() async throws -> CLLocation {
        guard continuation == nil else { throw LocationError(errorDescription: "Already locating.") }
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError(errorDescription: "Location access is off for Perigee. Enter coordinates manually or enable it in system settings.")
        default: break
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in if let l = locations.last { continuation?.resume(returning: l); continuation = nil } }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in continuation?.resume(throwing: LocationError(errorDescription: "Couldn't get your location: \(error.localizedDescription)")); continuation = nil }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied { continuation?.resume(throwing: LocationError(errorDescription: "Location access was denied.")); continuation = nil }
            else if status != .notDetermined { self.manager.requestLocation() }
        }
    }
}
