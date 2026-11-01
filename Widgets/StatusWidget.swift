import WidgetKit
import SwiftUI
import StarlinkKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot?
}

/// Reads the shared `SnapshotStore` only — the widget process never holds a gRPC connection of its own.
/// Refreshed on the system's own ~15-minute widget budget; the app also calls `WidgetCenter.reloadAllTimelines()`
/// after every poll while it's open, so the widget stays current whenever Perigee is running.
struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: StatusSnapshot(status: .online, statusText: "Online", internetPingMs: 23, obstructionFraction: 0.001, clientCount: 6))
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: SnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: SnapshotStore.read())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        Group {
            if let s = entry.snapshot { content(s) } else { empty }
        }
        .containerBackground(.black, for: .widget)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.title2).foregroundStyle(.secondary)
            Text("Open Perigee").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func content(_ s: StatusSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.caption)
                Text(s.internetPingMs.map { "\(Int($0))" } ?? "—").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(color(s.status))

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Circle().fill(color(s.status)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.statusText).font(.headline)
                    Text(subtitle(s)).font(.caption2).foregroundStyle(.secondary)
                }
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(color(s.status)).frame(width: 9, height: 9)
                    Text(s.statusText).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text(s.internetPingMs.map { "\(Int($0)) ms" } ?? "—").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle(s)).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                (Text("Updated ") + Text(s.updatedAt, style: .relative) + Text(" ago")).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func subtitle(_ s: StatusSnapshot) -> String {
        guard let o = s.obstructionFraction else { return "\(s.clientCount) devices" }
        return String(format: "%.2f%% obstructed · %d devices", o * 100, s.clientCount)
    }
    private func color(_ status: StatusSnapshot.Status) -> Color {
        switch status {
        case .online: .green
        case .degraded: .orange
        case .offline: .red
        case .connecting: .blue
        }
    }
}

struct StatusWidget: Widget {
    let kind = "dev.noktirnal.perigee.status"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Perigee Status")
        .description("Your Starlink link status, ping and obstruction.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
