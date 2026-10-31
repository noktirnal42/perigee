import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import DishAPI

public typealias DishRequest = DishAPI.SpaceX_API_Device_Request
public typealias DishResponse = DishAPI.SpaceX_API_Device_Response

/// Anything that can answer a dish `Handle` call: the real gRPC channel, the safety guard, or a mock.
public protocol DishTransport: Sendable {
    func handle(_ request: DishRequest) async throws -> DishResponse
}

/// Real plaintext HTTP/2 gRPC connection to a Starlink dish (default 192.168.100.1:9200).
public final class GRPCDishTransport: DishTransport, @unchecked Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let runTask: Task<Void, Never>
    private let timeout: Duration

    public init(host: String = "192.168.100.1", port: Int = 9200, timeout: Duration = .seconds(6)) throws {
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

    public func handle(_ request: DishRequest) async throws -> DishResponse {
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
public struct GuardedDishTransport: DishTransport {
    public let base: any DishTransport
    public let gate: WriteGate
    public init(base: any DishTransport, gate: WriteGate) { self.base = base; self.gate = gate }

    public func handle(_ request: DishRequest) async throws -> DishResponse {
        guard let name = MethodPolicy.caseName(of: request.request) else {
            throw DeviceError.safety(.emptyRequest)
        }
        do { try gate.authorize(name) } catch let e as SafetyError { throw DeviceError.safety(e) }
        return try await base.handle(request)
    }
}
