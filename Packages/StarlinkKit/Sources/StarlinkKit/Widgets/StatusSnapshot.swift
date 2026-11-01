import Foundation

/// A tiny, cheap-to-read snapshot of "what's going on right now," written by the main app on every poll and
/// read by the widget extension and headless App Intents — neither of which can hold a live gRPC connection
/// or see `StarlinkSession`. Nothing here is written to or read from anywhere but the app's own App Group
/// container: no server, no account.
public struct StatusSnapshot: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable { case online, degraded, offline, connecting }

    public var updatedAt: Date
    public var status: Status
    public var statusText: String
    public var internetPingMs: Double?
    public var obstructionFraction: Double?
    public var clientCount: Int

    public init(updatedAt: Date = Date(), status: Status, statusText: String, internetPingMs: Double? = nil,
                obstructionFraction: Double? = nil, clientCount: Int = 0) {
        self.updatedAt = updatedAt; self.status = status; self.statusText = statusText
        self.internetPingMs = internetPingMs; self.obstructionFraction = obstructionFraction; self.clientCount = clientCount
    }
}
