import Foundation
import GRPCCore

/// A user-presentable classification of what went wrong talking to a device.
public enum DeviceError: Error, Sendable, Equatable, LocalizedError {
    case permissionDenied(method: String)
    case unreachable(String)
    case timeout
    case authRequired
    case unimplemented(method: String)
    case malformedResponse(String)
    case remote(code: String, message: String)
    case safety(SafetyError)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let m):
            isWriteRefusal
            ? "The router refused this change from the local network (PermissionDenied on “\(m)”). It most likely requires Starlink account authentication, which Perigee deliberately never uses, so settings are view-only here."
            : "The device refused “\(m)” from the local network (PermissionDenied)."
        case .unreachable(let why): "Can't reach the device. \(why)"
        case .timeout: "The device took too long to answer."
        case .authRequired: "This needs authentication that isn't available over the LAN."
        case .unimplemented(let m): "This firmware doesn't implement “\(m)”."
        case .malformedResponse(let s): "Unexpected response: \(s)"
        case .remote(let c, let m): "Device error \(c): \(m)"
        case .safety(let e): e.errorDescription
        }
    }

    public var isPermissionDenied: Bool { if case .permissionDenied = self { true } else { false } }

    /// PermissionDenied on a method that changes configuration (as opposed to a refused read).
    public var isWriteRefusal: Bool {
        guard case .permissionDenied(let m) = self else { return false }
        let camel = MethodPolicy.classify(m)
        if camel == .write || camel == .destructive { return true }
        return ["wifi_set_config", "wifi_set_client_given_name", "dish_set_config", "reboot", "dish_stow"].contains(m)
    }

    static func map(_ error: any Error, method: String) -> DeviceError {
        if let d = error as? DeviceError { return d }
        if let s = error as? SafetyError { return .safety(s) }
        if let r = error as? RPCError {
            switch r.code {
            case .permissionDenied: return .permissionDenied(method: method)
            case .unauthenticated: return .authRequired
            case .unimplemented: return .unimplemented(method: method)
            case .deadlineExceeded: return .timeout
            case .unavailable: return .unreachable(r.message)
            default: return .remote(code: "\(r.code)", message: r.message)
            }
        }
        if error is CancellationError { return .timeout }
        return .unreachable(String(describing: error))
    }
}
