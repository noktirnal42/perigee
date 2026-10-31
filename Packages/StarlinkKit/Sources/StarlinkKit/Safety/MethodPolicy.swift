import Foundation

/// How dangerous a device method is. Every request the app sends is classified by name;
/// anything not explicitly listed is `.forbidden` and can never be sent.
public enum MethodClass: String, Sendable, Codable {
    /// Pure read. Always allowed.
    case read
    /// Generates traffic or runs a measurement but changes no configuration. Always allowed.
    case probe
    /// Changes configuration. Requires "Enable writes".
    case write
    /// Reboots/stows hardware. Requires "Enable writes" AND an explicit per-call confirmation.
    case destructive
    /// Never sent by this app (auth, signing, debug, test modes, factory resets, firmware...).
    case forbidden
}

public enum MethodPolicy {
    // Names are the Swift (lowerCamelCase) spellings of the proto `Request` oneof cases.
    static let reads: Set<String> = [
        "getStatus", "getHistory", "getDeviceInfo", "getPing", "getLog", "getNetworkInterfaces",
        "getLocation", "getPersistentStats", "getConnections", "getSpeedtestStatus",
        "getRadioStats", "time", "getDiagnostics",
        "dishGetContext", "dishGetObstructionMap", "dishGetConfig", "dishGetEmc",
        "wifiGetClients", "wifiGetPingMetrics", "wifiGetConfig", "wifiGetClientHistory",
        "wifiGuestInfo", "wifiGetFirewall", "wifiBackhaulStats", "wifiGetTracerouteStatus",
        "wifiGetChannels", "transceiverGetStatus",
    ]
    static let probes: Set<String> = ["startSpeedtest", "wifiStartTraceroute", "pingHost"]
    static let writes: Set<String> = [
        "wifiSetConfig", "wifiSetClientGivenName", "dishSetConfig",
        "wifiSetMeshConfig", "wifiSetMeshDeviceTrust",
    ]
    static let destructives: Set<String> = ["reboot", "dishStow"]

    /// Names that must stay forbidden even if someone later edits the sets above (checked in tests).
    public static let neverAllowed: Set<String> = [
        "authenticate", "signedRequest", "sensitiveRequest", "initiateRemoteSsh",
        "factoryReset", "dishFactoryReset", "enableDebugTelem", "setTestMode", "toggleMode",
        "dishSetMaxPowerTestMode", "dishAviationTest", "wifiFactoryTestCommand", "fuse",
        "setSku", "setTrustedKeys", "softwareUpdate", "update", "startUnlock", "finishUnlock",
        "wifiCalibrationMode", "wifiWriteCalibration", "iqCapture", "wifiSetAviationConformed",
        "dishInhibitRf", "dishInhibitGps", "resetButton", "wifiRfTest", "wifiSetup",
    ]

    public static func classify(_ method: String) -> MethodClass {
        if neverAllowed.contains(method) { return .forbidden }
        if reads.contains(method) { return .read }
        if probes.contains(method) { return .probe }
        if writes.contains(method) { return .write }
        if destructives.contains(method) { return .destructive }
        return .forbidden
    }

    /// Case label of a oneof enum value, via reflection (`getStatus`, `wifiSetConfig`, ...).
    public static func caseName(of oneof: Any?) -> String? {
        guard let oneof else { return nil }
        return Mirror(reflecting: oneof).children.first?.label
    }
}

public enum SafetyError: Error, Sendable, Equatable, LocalizedError {
    case forbidden(method: String)
    case readOnlyMode(method: String)
    case confirmationRequired(method: String)
    case emptyRequest

    public var errorDescription: String? {
        switch self {
        case .forbidden(let m): "“\(m)” is blocked by Perigee's safety policy and can never be sent."
        case .readOnlyMode(let m): "Writes are disabled. Turn on “Enable writes” to send “\(m)”."
        case .confirmationRequired(let m): "“\(m)” needs an explicit slide-to-confirm."
        case .emptyRequest: "Empty request."
        }
    }
}

/// Process-wide switchboard for write permission. One instance is shared by both device transports.
public final class WriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _writesEnabled = false
    public init(writesEnabled: Bool = false) { _writesEnabled = writesEnabled }

    public var writesEnabled: Bool {
        get { lock.withLock { _writesEnabled } }
        set { lock.withLock { _writesEnabled = newValue } }
    }

    /// Throws unless `method` may be sent right now.
    public func authorize(_ method: String) throws {
        switch MethodPolicy.classify(method) {
        case .read, .probe: return
        case .forbidden: throw SafetyError.forbidden(method: method)
        case .write:
            guard writesEnabled else { throw SafetyError.readOnlyMode(method: method) }
        case .destructive:
            guard writesEnabled else { throw SafetyError.readOnlyMode(method: method) }
            guard DestructiveConfirmation.isConfirmed else { throw SafetyError.confirmationRequired(method: method) }
        }
    }
}

/// Destructive calls (reboot, stow) only go through inside `DestructiveConfirmation.run { }`,
/// which the UI invokes exclusively from a completed slide-to-confirm.
public enum DestructiveConfirmation {
    @TaskLocal static var isConfirmed = false
    public static func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        try await $isConfirmed.withValue(true) { try await body() }
    }
}
