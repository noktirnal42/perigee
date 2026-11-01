import Foundation

public enum CapabilityState: Sendable, Equatable, Codable {
    case unknown
    case available
    case denied          // PermissionDenied from the LAN
    case unsupported     // firmware doesn't implement it
    case failed(String)

    public var isUsable: Bool { self == .available || self == .unknown }
}

public struct Capability: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(device.rawValue):\(method)" }
    public var method: String        // proto method name, e.g. wifi_get_channels
    public var title: String
    public var detail: String        // what the app uses it for
    public var state: CapabilityState
    public var device: DeviceKind
    public init(method: String, title: String, detail: String, state: CapabilityState = .unknown, device: DeviceKind) {
        self.method = method; self.title = title; self.detail = detail; self.state = state; self.device = device
    }

    /// Plain-language reason shown when a feature is greyed out.
    public var explanation: String {
        switch state {
        case .unknown: "Not checked yet."
        case .available: "Available."
        case .denied: "The device denied this request on the local network. The required authorization is unknown."
        case .unsupported: "This firmware doesn't implement it."
        case .failed(let s): "Failed: \(s)"
        }
    }
}

public enum DeviceKind: String, Sendable, Codable { case router, dish }

/// Remembers what each method answered so the UI can explain unavailable features instead of failing silently.
public final class CapabilityBook: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: CapabilityState] = [:]
    public init() {}

    public func record(_ method: String, _ state: CapabilityState) { lock.withLock { states[method] = state } }
    public func state(_ method: String) -> CapabilityState { lock.withLock { states[method] ?? .unknown } }
    public func snapshot() -> [String: CapabilityState] { lock.withLock { states } }

    func record(_ method: String, error: DeviceError) {
        switch error {
        case .permissionDenied: record(method, .denied)
        case .unimplemented: record(method, .unsupported)
        case .authRequired: record(method, .denied)
        default: break  // transient failures don't change what the device allows
        }
    }
}

/// The read-only calls the app probes at connect time, in the order they're shown.
public enum KnownCapabilities {
    public static let router: [Capability] = [
        .init(method: "get_status", title: "Router status", detail: "Online state, latency, alerts, WAN addresses.", device: .router),
        .init(method: "wifi_get_clients", title: "Connected devices", detail: "Device list with RSSI, link rate and bands.", device: .router),
        .init(method: "wifi_get_config", title: "Wi-Fi configuration", detail: "Channels, widths, power, DNS and traffic control.", device: .router),
        .init(method: "get_radio_stats", title: "Radio health", detail: "Per-band frame errors, temperature and antenna RSSI.", device: .router),
        .init(method: "get_history", title: "Router history", detail: "Latency and packet-loss graphs, event log.", device: .router),
        .init(method: "wifi_get_channels", title: "Channel survey", detail: "Which channels are allowed and congested.", device: .router),
        .init(method: "wifi_get_ping_metrics", title: "Ping metrics", detail: "Router-side ping breakdown.", device: .router),
        .init(method: "wifi_get_client_history", title: "Per-device history", detail: "Throughput history for one device.", device: .router),
        .init(method: "get_speedtest_status", title: "Speed test", detail: "Status of the router's speed test.", device: .router),
        .init(method: "wifi_get_traceroute_status", title: "Traceroute", detail: "Router-side traceroute results.", device: .router),
        .init(method: "get_log", title: "System log", detail: "Router syslog viewer.", device: .router),
    ]
    public static let dish: [Capability] = [
        .init(method: "get_status", title: "Dish status", detail: "Throughput, ping, obstruction, alignment, alerts.", device: .dish),
        .init(method: "dish_get_config", title: "Dish configuration", detail: "Snow melt, sleep schedule, update window.", device: .dish),
        .init(method: "dish_get_obstruction_map", title: "Obstruction map", detail: "Sky view of blocked sectors.", device: .dish),
        .init(method: "get_history", title: "Dish history", detail: "15-minute ping, throughput and outage history.", device: .dish),
        .init(method: "get_location", title: "Dish GPS location", detail: "Where the dish is. Disabled by policy over the LAN, so Perigee asks for your location instead.", device: .dish),
    ]
}
