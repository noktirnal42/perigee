import SwiftUI
import StarlinkKit

/// Loads just enough to compute `Forecast.windows(...)` for the Home screen: the same bundled/cached orbital
/// data the Sky screen uses, the saved observer location, and the last week of history. Independent of
/// `SkyModel` so this card works without ever opening the Sky tab.
@MainActor @Observable
final class ForecastCardModel {
    var windows: [RiskWindow] = []
    var loaded = false

    private let store = ConstellationStore()

    func refresh(session: StarlinkSession) async {
        let observer: Observer? = {
            let d = UserDefaults.standard
            guard d.object(forKey: "observer.lat") != nil else { return nil }
            let o = Observer(latitude: d.double(forKey: "observer.lat"), longitude: d.double(forKey: "observer.lon"), altitudeMeters: d.double(forKey: "observer.alt"))
            return o.isValid ? o : nil
        }()
        let constellation = await store.load(allowDownload: session.source == .live)
        let buckets = await session.history.buckets(resolution: .hour, since: Date().addingTimeInterval(-7 * 86400))
        windows = Forecast.windows(constellation: constellation, observer: observer, historyBuckets: buckets)
        loaded = true
    }
}

/// A Home-screen card for upcoming "might be rougher than usual" windows. Always framed as an estimate —
/// Perigee's own heuristic from public orbital data and this device's own history, never a Starlink fact.
struct ForecastCard: View {
    @Environment(StarlinkSession.self) private var session
    @State private var model = ForecastCardModel()

    var body: some View {
        Group {
            if let next = model.windows.first {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Possible rough window ahead", systemImage: "cloud.sun.rain")
                        .font(.headline)
                    Text("\(Fmt.time(next.start)) – \(Fmt.time(next.end))")
                        .font(.numeral(20))
                    ForEach(next.reasons, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    Text("An estimate from public orbital data and this device's own history — not something Starlink publishes, and it can be wrong.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.info)
            }
        }
        .task { await model.refresh(session: session) }
    }
}
