import Foundation

public enum RadioBand: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case ghz2, ghz5, ghz5High, ethernet, unknown
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .ghz2: "2.4 GHz"
        case .ghz5: "5 GHz"
        case .ghz5High: "5 GHz High"
        case .ethernet: "Ethernet"
        case .unknown: "Unknown"
        }
    }
    public var short: String {
        switch self { case .ghz2: "2.4"; case .ghz5: "5"; case .ghz5High: "5H"; case .ethernet: "ETH"; case .unknown: "?" }
    }
    /// The wireless bands that can be tuned.
    public static let tunable: [RadioBand] = [.ghz2, .ghz5, .ghz5High]
}

public struct DeviceIdentity: Sendable, Equatable, Codable {
    public var id: String
    public var hardwareVersion: String
    public var softwareVersion: String
    public var countryCode: String
    public var bootCount: Int
    public var uptime: TimeInterval
    public init(id: String = "", hardwareVersion: String = "", softwareVersion: String = "", countryCode: String = "",
                bootCount: Int = 0, uptime: TimeInterval = 0) {
        self.id = id; self.hardwareVersion = hardwareVersion; self.softwareVersion = softwareVersion
        self.countryCode = countryCode; self.bootCount = bootCount; self.uptime = uptime
    }
}

public struct BandAirtime: Sendable, Equatable, Codable {
    public var busy: Double      // 0...1
    public var tx: Double
    public var rx: Double
    public var otherNetworks: Double   // OBSS: other Wi-Fi networks sharing the channel
    public var interference: Double    // EDCCA: non-Wi-Fi energy
    public init(busy: Double = 0, tx: Double = 0, rx: Double = 0, otherNetworks: Double = 0, interference: Double = 0) {
        self.busy = busy; self.tx = tx; self.rx = rx; self.otherNetworks = otherNetworks; self.interference = interference
    }
}

public struct RouterStatus: Sendable, Equatable, Codable {
    public var identity: DeviceIdentity
    public var wanIPv4: String
    public var publicIPv4: String
    public var ipv6: [String]
    public var internetPingMs: Double?
    public var dishPingMs: Double?
    public var popPingMs: Double?
    public var popPingIPv6Ms: Double?
    public var pingDropRate: Double?       // 0...1, last sample
    public var pingDropRate5m: Double?
    public var popPingDropRate5m: Double?
    public var alerts: [String]
    public var dishId: String
    public var dishDisablement: String
    public var softwareUpdateState: String
    public var airtime2: BandAirtime?
    public var airtime5: BandAirtime?
    public var clientCount: Int
    public var noWanLink: Bool
    public init(identity: DeviceIdentity = .init(), wanIPv4: String = "", publicIPv4: String = "", ipv6: [String] = [],
                internetPingMs: Double? = nil, dishPingMs: Double? = nil, popPingMs: Double? = nil,
                popPingIPv6Ms: Double? = nil, pingDropRate: Double? = nil, pingDropRate5m: Double? = nil,
                popPingDropRate5m: Double? = nil, alerts: [String] = [], dishId: String = "",
                dishDisablement: String = "", softwareUpdateState: String = "", airtime2: BandAirtime? = nil,
                airtime5: BandAirtime? = nil, clientCount: Int = 0, noWanLink: Bool = false) {
        self.identity = identity; self.wanIPv4 = wanIPv4; self.publicIPv4 = publicIPv4; self.ipv6 = ipv6
        self.internetPingMs = internetPingMs; self.dishPingMs = dishPingMs; self.popPingMs = popPingMs
        self.popPingIPv6Ms = popPingIPv6Ms; self.pingDropRate = pingDropRate; self.pingDropRate5m = pingDropRate5m
        self.popPingDropRate5m = popPingDropRate5m; self.alerts = alerts; self.dishId = dishId
        self.dishDisablement = dishDisablement; self.softwareUpdateState = softwareUpdateState
        self.airtime2 = airtime2; self.airtime5 = airtime5; self.clientCount = clientCount; self.noWanLink = noWanLink
    }
}

public struct LinkStats: Sendable, Equatable, Codable, Hashable {
    public var rateMbps: Double
    public var throughputMbps: Double
    public var mcs: Int
    public var nss: Int
    public var widthMHz: Int
    public init(rateMbps: Double = 0, throughputMbps: Double = 0, mcs: Int = 0, nss: Int = 0, widthMHz: Int = 0) {
        self.rateMbps = rateMbps; self.throughputMbps = throughputMbps; self.mcs = mcs; self.nss = nss; self.widthMHz = widthMHz
    }
}

public struct NetworkClient: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UInt32            // device-assigned client id (MACs are partially masked by the router)
    public var name: String
    public var givenName: String
    public var mac: String
    public var ip: String
    public var band: RadioBand
    public var role: String          // CLIENT / CONTROLLER / REPEATER
    public var rssi: Double?
    public var snr: Double?
    public var channelWidthMHz: Int
    public var rx: LinkStats
    public var tx: LinkStats
    public var associatedSeconds: Int
    public var upstreamMac: String
    public var hops: Int
    public var wifiMode: String
    public var downloadMB: Int
    public var uploadMB: Int
    public var dscpTrafficBytes: [String: Double]  // WMM classes → bytes (best-effort)

    public init(id: UInt32 = 0, name: String = "", givenName: String = "", mac: String = "", ip: String = "",
                band: RadioBand = .unknown, role: String = "CLIENT", rssi: Double? = nil, snr: Double? = nil,
                channelWidthMHz: Int = 0, rx: LinkStats = .init(), tx: LinkStats = .init(), associatedSeconds: Int = 0,
                upstreamMac: String = "", hops: Int = 0, wifiMode: String = "", downloadMB: Int = 0, uploadMB: Int = 0,
                dscpTrafficBytes: [String: Double] = [:]) {
        self.id = id; self.name = name; self.givenName = givenName; self.mac = mac; self.ip = ip; self.band = band
        self.role = role; self.rssi = rssi; self.snr = snr; self.channelWidthMHz = channelWidthMHz; self.rx = rx
        self.tx = tx; self.associatedSeconds = associatedSeconds; self.upstreamMac = upstreamMac; self.hops = hops
        self.wifiMode = wifiMode; self.downloadMB = downloadMB; self.uploadMB = uploadMB
        self.dscpTrafficBytes = dscpTrafficBytes
    }

    /// The name to show: the user's given name wins, then the device-reported one, then the IP.
    public var displayName: String {
        if !givenName.isEmpty { return givenName }
        if !name.isEmpty { return name }
        return ip.isEmpty ? "Unknown device" : ip
    }
    public var isWireless: Bool { band != .ethernet && band != .unknown }
    public var isController: Bool { role == "CONTROLLER" }
    public var vendor: String { MACVendor.describe(mac) }
}

public struct RadioStat: Sendable, Equatable, Codable, Identifiable {
    public var id: RadioBand { band }
    public var band: RadioBand
    public var rxPackets: UInt64
    public var rxFrameErrors: UInt64
    public var txPackets: UInt64
    public var temperatureC: Double?
    public var dutyCycle: Double?
    public var rssi: [Double]   // per antenna, NaN removed
    public init(band: RadioBand, rxPackets: UInt64 = 0, rxFrameErrors: UInt64 = 0, txPackets: UInt64 = 0,
                temperatureC: Double? = nil, dutyCycle: Double? = nil, rssi: [Double] = []) {
        self.band = band; self.rxPackets = rxPackets; self.rxFrameErrors = rxFrameErrors; self.txPackets = txPackets
        self.temperatureC = temperatureC; self.dutyCycle = dutyCycle; self.rssi = rssi
    }
    /// Frame errors per received frame (0...1). Counters are cumulative since boot.
    public var frameErrorRate: Double {
        let total = Double(rxPackets + rxFrameErrors)
        return total > 0 ? Double(rxFrameErrors) / total : 0
    }
}

public struct HistorySeries: Sendable, Equatable, Codable {
    /// Oldest → newest, one sample per `interval` seconds. `nil` = no data for that sample.
    public var latencyMs: [Double?]
    public var dropRate: [Double?]
    public var interval: TimeInterval
    public var events: [DeviceEvent]
    public init(latencyMs: [Double?] = [], dropRate: [Double?] = [], interval: TimeInterval = 1, events: [DeviceEvent] = []) {
        self.latencyMs = latencyMs; self.dropRate = dropRate; self.interval = interval; self.events = events
    }
}

public struct DeviceEvent: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(start.timeIntervalSince1970)-\(reason)" }
    public var severity: String
    public var reason: String
    public var start: Date
    public var duration: TimeInterval
    public init(severity: String, reason: String, start: Date, duration: TimeInterval) {
        self.severity = severity; self.reason = reason; self.start = start; self.duration = duration
    }
    public var title: String {
        reason.replacingOccurrences(of: "EVENT_REASON_", with: "")
            .replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct DishStatus: Sendable, Equatable, Codable {
    public var identity: DeviceIdentity
    public var popPingMs: Double?
    public var popPingDropRate: Double?
    public var downlinkBps: Double
    public var uplinkBps: Double
    public var obstructionFraction: Double?
    public var obstructionValidSeconds: Double
    public var azimuthDeg: Double?
    public var elevationDeg: Double?
    public var tiltDeg: Double?
    public var alerts: [String]
    public var softwareUpdateState: String
    public var disablementCode: String
    public var snowMeltActive: Bool
    public var ethSpeedMbps: Int
    public var mobility: String
    public var classOfService: String
    public var hasActuators: Bool
    public var stowRequested: Bool
    public var dlRestricted: String
    public var ulRestricted: String
    public var signalAboveNoise: Bool
    public var gpsLocked: Bool
    public var hardwareHealthy: Bool
    public var config: DishSettings
    public init(identity: DeviceIdentity = .init(), popPingMs: Double? = nil, popPingDropRate: Double? = nil,
                downlinkBps: Double = 0, uplinkBps: Double = 0, obstructionFraction: Double? = nil,
                obstructionValidSeconds: Double = 0, azimuthDeg: Double? = nil, elevationDeg: Double? = nil,
                tiltDeg: Double? = nil, alerts: [String] = [], softwareUpdateState: String = "",
                disablementCode: String = "", snowMeltActive: Bool = false, ethSpeedMbps: Int = 0,
                mobility: String = "", classOfService: String = "", hasActuators: Bool = false,
                stowRequested: Bool = false, dlRestricted: String = "", ulRestricted: String = "",
                signalAboveNoise: Bool = true, gpsLocked: Bool = true, hardwareHealthy: Bool = true,
                config: DishSettings = .init()) {
        self.identity = identity; self.popPingMs = popPingMs; self.popPingDropRate = popPingDropRate
        self.downlinkBps = downlinkBps; self.uplinkBps = uplinkBps; self.obstructionFraction = obstructionFraction
        self.obstructionValidSeconds = obstructionValidSeconds; self.azimuthDeg = azimuthDeg
        self.elevationDeg = elevationDeg; self.tiltDeg = tiltDeg; self.alerts = alerts
        self.softwareUpdateState = softwareUpdateState; self.disablementCode = disablementCode
        self.snowMeltActive = snowMeltActive; self.ethSpeedMbps = ethSpeedMbps; self.mobility = mobility
        self.classOfService = classOfService; self.hasActuators = hasActuators; self.stowRequested = stowRequested
        self.dlRestricted = dlRestricted; self.ulRestricted = ulRestricted; self.signalAboveNoise = signalAboveNoise
        self.gpsLocked = gpsLocked; self.hardwareHealthy = hardwareHealthy; self.config = config
    }
}

public struct DishHistory: Sendable, Equatable, Codable {
    public var latencyMs: [Double?]
    public var dropRate: [Double?]
    public var downlinkBps: [Double]
    public var uplinkBps: [Double]
    public var outages: [DeviceEvent]
    public init(latencyMs: [Double?] = [], dropRate: [Double?] = [], downlinkBps: [Double] = [], uplinkBps: [Double] = [], outages: [DeviceEvent] = []) {
        self.latencyMs = latencyMs; self.dropRate = dropRate; self.downlinkBps = downlinkBps
        self.uplinkBps = uplinkBps; self.outages = outages
    }
}

public struct ObstructionMap: Sendable, Equatable, Codable {
    public var rows: Int
    public var cols: Int
    /// Row-major SNR values; negative = no data (unobserved), 0 = obstructed, ~1 = clear.
    public var snr: [Float]
    public var minElevationDeg: Double
    public var maxThetaDeg: Double
    public init(rows: Int, cols: Int, snr: [Float], minElevationDeg: Double = 20, maxThetaDeg: Double = 80) {
        self.rows = rows; self.cols = cols; self.snr = snr; self.minElevationDeg = minElevationDeg; self.maxThetaDeg = maxThetaDeg
    }
    public func value(row: Int, col: Int) -> Float {
        guard row >= 0, col >= 0, row < rows, col < cols, row * cols + col < snr.count else { return -1 }
        return snr[row * cols + col]
    }
}

public struct TracerouteHop: Sendable, Equatable, Codable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var address: String
    public var rttMs: [Double]
    public init(index: Int, address: String, rttMs: [Double]) { self.index = index; self.address = address; self.rttMs = rttMs }
}

public struct TracerouteResult: Sendable, Equatable, Codable {
    public var state: String
    public var target: String
    public var hops: [TracerouteHop]
    public init(state: String, target: String, hops: [TracerouteHop]) { self.state = state; self.target = target; self.hops = hops }
    public var isFinished: Bool { state.uppercased().contains("COMPLETE") || state.uppercased().contains("DONE") || state.uppercased().contains("FINISH") }
}

public struct SpeedtestState: Sendable, Equatable, Codable {
    public var running: Bool
    public var downMbps: Double?
    public var upMbps: Double?
    public init(running: Bool, downMbps: Double? = nil, upMbps: Double? = nil) { self.running = running; self.downMbps = downMbps; self.upMbps = upMbps }
}

public struct ClientHistory: Sendable, Equatable, Codable {
    public var txMbps: [Double]
    public var rxMbps: [Double]
    public var rxRateMbps: [Double]
    public init(txMbps: [Double] = [], rxMbps: [Double] = [], rxRateMbps: [Double] = []) {
        self.txMbps = txMbps; self.rxMbps = rxMbps; self.rxRateMbps = rxRateMbps
    }
}

/// Coarse vendor lookup. Modern phones/laptops randomise their Wi-Fi MAC, which the router also partially masks.
public enum MACVendor {
    private static let table: [String: String] = [
        "74:24:9f": "Starlink", "f4:f5:d8": "Google", "3c:5a:b4": "Google", "00:50:f2": "Microsoft", "7c:1e:52": "Microsoft",
        "98:5f:d3": "Microsoft", "28:18:78": "Microsoft", "a4:5e:60": "Apple", "f0:18:98": "Apple", "3c:07:54": "Apple",
        "dc:a6:32": "Raspberry Pi", "b8:27:eb": "Raspberry Pi", "fc:a1:83": "Amazon", "44:65:0d": "Amazon",
        "ac:63:be": "Amazon", "00:04:4b": "NVIDIA", "78:d6:f0": "Samsung", "8c:f5:a3": "Samsung", "00:1a:11": "Google",
        "d8:eb:46": "Google", "b0:be:76": "TP-Link", "50:c7:bf": "TP-Link", "00:0d:4b": "Roku", "b8:3e:59": "Roku",
        "7c:bb:8a": "Nintendo", "e8:4e:ce": "Nintendo", "00:d9:d1": "Sony", "fc:0f:e6": "Sony", "70:9e:29": "Sony",
    ]
    public static func describe(_ mac: String) -> String {
        let m = mac.lowercased()
        let parts = m.split(separator: ":")
        guard parts.count >= 3, let first = UInt8(parts[0], radix: 16) else { return "Unknown vendor" }
        if let v = table[parts[0...2].joined(separator: ":")] { return v }
        if first & 0x02 != 0 { return "Private address" }   // locally-administered bit → randomised MAC
        return "Unknown vendor"
    }
}
