import SwiftUI
import StarlinkKit
#if os(iOS)
import WidgetKit
#endif

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, network, tune, dish, diagnostics, trends
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"; case .network: "Network"; case .tune: "Tune"; case .dish: "Dish"
        case .diagnostics: "Diagnose"; case .trends: "Trends"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"; case .network: "wifi"; case .tune: "slider.horizontal.3"
        case .dish: "antenna.radiowaves.left.and.right"; case .diagnostics: "waveform.path.ecg"
        case .trends: "chart.xyaxis.line"
        }
    }
}

struct RootView: View {
    @Environment(StarlinkSession.self) private var session
    @State private var selection: AppSection = {
        // `-tab network` etc. jumps straight to a screen (screenshots, UI tests).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let s = AppSection(rawValue: args[i + 1]) { return s }
        return .home
    }()

    var body: some View {
        content
            .tint(Theme.ember)
            .preferredColorScheme(.dark)
            .task { session.start(); AlertNotifier.requestAuthorization() }
            .onChange(of: session.pendingAlerts.count) { _, _ in
                for alert in session.consumePendingAlerts() { AlertNotifier.post(alert) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .perigeeOpenDiagnostics)) { _ in selection = .diagnostics }
            .onReceive(NotificationCenter.default.publisher(for: .perigeeOpenTune)) { _ in selection = .tune }
            .overlay(alignment: .top) { if session.writesEnabled { WritesBanner() } }
            #if os(iOS)
            .onChange(of: session.lastUpdated) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
            #endif
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding<AppSection?>(get: { selection }, set: { selection = $0 ?? .home })) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(12) }
        } detail: {
            NavigationStack { screen(selection) }
                .toolbar {
                    ToolbarItem { Button { Task { await session.refreshNow() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.keyboardShortcut("r") }
                }
        }
        #else
        Group {
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                tabs
            }
        }
        #endif
    }

    #if os(iOS)
    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { s in
                Tab(s.title, systemImage: s.symbol, value: s) { NavigationStack { screen(s) } }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #endif

    @ViewBuilder private func screen(_ s: AppSection) -> some View {
        switch s {
        case .home: HomeView(selection: $selection)
        case .network: NetworkView()
        case .tune: TuneView()
        case .dish: DishHub()
        case .diagnostics: DiagnosticsView()
        case .trends: TrendsView()
        }
    }
}

struct WritesBanner: View {
    var body: some View {
        Text("WRITES ENABLED").font(.system(size: 10, weight: .heavy).width(.expanded)).tracking(2)
            .padding(.horizontal, 12).padding(.vertical, 4).background(Theme.warn, in: Capsule()).foregroundStyle(.black)
            .padding(.top, 2).allowsHitTesting(false).accessibilityLabel("Writes are enabled")
    }
}

struct SidebarStatus: View {
    @Environment(StarlinkSession.self) private var session
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption.weight(.semibold))
                Text(session.source == .demo ? "Demo data" : (session.routerStatus?.internetPingMs).map { "\(Fmt.ms($0)) ms" } ?? "—").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private var color: Color { switch session.link { case .online: Theme.good; case .degraded: Theme.warn; case .offline: Theme.bad; case .connecting: Theme.info } }
    private var label: String { switch session.link { case .online: "Online"; case .degraded: "Degraded"; case .offline: "Offline"; case .connecting: "Connecting" } }
}
