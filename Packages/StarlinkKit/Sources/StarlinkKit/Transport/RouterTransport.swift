import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import RouterAPI

public typealias RouterRequest = RouterAPI.SpaceX_API_Device_Request
public typealias RouterResponse = RouterAPI.SpaceX_API_Device_Response

/// Anything that can answer a router `Handle` call: the real gRPC channel, the safety guard, or a mock.
public protocol RouterTransport: Sendable {
    func handle(_ request: RouterRequest) async throws -> RouterResponse
}

/// Real plaintext HTTP/2 gRPC connection to a Starlink router (default 192.168.1.1:9000).
public final class GRPCRouterTransport: RouterTransport, @unchecked Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let runTask: Task<Void, Never>
    private let timeout: Duration

    public init(host: String = "192.168.1.1", port: Int = 9000, timeout: Duration = .seconds(6)) throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: host, port: port),
            transportSecurity: .plaintext
        )
        let client = GRPCClient(transport: transport)
        self.client = client
        self.timeout = timeout
        self.runTask = Task { try? await client.runConnections() }
    }

    deinit {
        client.beginGracefulShutdown()
        runTask.cancel()
    }

    public func handle(_ request: RouterRequest) async throws -> RouterResponse {
        let device = SpaceX_API_Device_Device.Client(wrapping: client)
        var options = CallOptions.defaults
        options.timeout = timeout
        let name = MethodPolicy.caseName(of: request.request) ?? "?"
        do {
            return try await device.handle(request, options: options)
        } catch {
            throw DeviceError.map(error, method: name)
        }
    }
}

/// Wraps any transport with the safety policy. This is the single choke point every call passes through.
public struct GuardedRouterTransport: RouterTransport {
    public let base: any RouterTransport
    public let gate: WriteGate
    public init(base: any RouterTransport, gate: WriteGate) { self.base = base; self.gate = gate }

    public func handle(_ request: RouterRequest) async throws -> RouterResponse {
        guard let name = MethodPolicy.caseName(of: request.request) else {
            throw DeviceError.safety(.emptyRequest)
        }
        do { try gate.authorize(name) } catch let e as SafetyError { throw DeviceError.safety(e) }
        return try await base.handle(request)
    }
}
