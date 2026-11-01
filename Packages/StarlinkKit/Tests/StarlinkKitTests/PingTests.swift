import Foundation
import Testing
@testable import StarlinkKit

@Suite("Ping reply validation")
struct PingTests {
    @Test func rejectsWrongTokenAndMalformedPackets() {
        let token: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        var reply = [UInt8](repeating: 0, count: 16)
        reply[7] = 42
        reply.replaceSubrange(8..<16, with: token)
        #expect(ICMPPinger.replySequence(reply[...], token: token) == 42)
        #expect(ICMPPinger.replySequence(reply[...], token: Array(repeating: 0, count: 8)) == nil)
        #expect(ICMPPinger.replySequence(reply.prefix(15), token: token) == nil)
        reply[0] = 8
        #expect(ICMPPinger.replySequence(reply[...], token: token) == nil)
    }

    @Test func handlesIPv4Header() {
        let token: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        var packet = [UInt8](repeating: 0, count: 36)
        packet[0] = 0x45
        packet[26] = 1; packet[27] = 2
        packet.replaceSubrange(28..<36, with: token)
        #expect(ICMPPinger.replySequence(packet[...], token: token) == 258)
        packet[0] = 0x44
        #expect(ICMPPinger.replySequence(packet[...], token: token) == nil)
    }

    @Test func validatesRunParameters() async {
        let pinger = ICMPPinger()
        await #expect(throws: PingError.self) {
            _ = try await pinger.run(host: "127.0.0.1", count: 0, interval: 0.2) { _ in }
        }
        await #expect(throws: PingError.self) {
            _ = try await pinger.run(host: "127.0.0.1", count: 1, interval: .nan) { _ in }
        }
    }
    @Test func cancelledTaskDoesNotReturnAResult() async {
        let task = Task {
            try await ICMPPinger().run(host: "127.0.0.1", count: 150, interval: 0.2) { _ in }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

}
