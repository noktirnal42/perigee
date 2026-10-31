import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum PingError: Error, Sendable, LocalizedError {
    case socket(String)
    case badAddress(String)
    public var errorDescription: String? {
        switch self { case .socket(let s): "Couldn't open a ping socket: \(s)"; case .badAddress(let a): "“\(a)” isn't an IPv4 address." }
    }
}

/// Unprivileged ICMP echo over a datagram socket (works in the iOS and macOS sandboxes, no root needed).
/// Probes are sent on a fixed clock regardless of replies — like `ping -i` — so stalls show up as gaps, not as slower pacing.
public final class ICMPPinger: @unchecked Sendable {
    private let lock = NSLock()
    private var sendTimes: [UInt64] = []
    private var rtts: [Double?] = []
    private var stop = false

    public init() {}

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    /// Runs `count` probes `interval` seconds apart. `progress` is called after each probe is sent with the samples so far.
    public func run(host: String, count: Int, interval: TimeInterval, timeout: TimeInterval = 1.0,
                    progress: @escaping @Sendable ([Double?]) -> Void) async throws -> [Double?] {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { throw PingError.badAddress(host) }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { throw PingError.socket(String(cString: strerror(errno))) }
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)   // wake the receiver regularly so it can notice `stop`
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        lock.withLock { sendTimes = Array(repeating: 0, count: count); rtts = Array(repeating: nil, count: count); stop = false }
        let ident = UInt16.random(in: 1...UInt16.max)

        let receiver = Thread { [self] in
            var buf = [UInt8](repeating: 0, count: 2048)
            while !lock.withLock({ stop }) {
                let n = recv(fd, &buf, buf.count, 0)
                guard n > 0 else { continue }
                let t = Self.now()
                // Datagram ICMP sockets deliver the IP header too.
                let ihl = Int(buf[0] & 0x0f) * 4
                guard Int(n) >= ihl + 8, buf[ihl] == 0 else { continue }   // type 0 = echo reply
                let seq = Int(UInt16(buf[ihl + 6]) << 8 | UInt16(buf[ihl + 7]))
                lock.withLock {
                    if seq < sendTimes.count, sendTimes[seq] != 0, rtts[seq] == nil {
                        rtts[seq] = Double(t - sendTimes[seq]) / 1e6
                    }
                }
            }
        }
        receiver.qualityOfService = .userInitiated
        receiver.start()
        defer { lock.withLock { stop = true }; close(fd) }

        let start = Self.now()
        for seq in 0..<count {
            var pkt = [UInt8](repeating: 0, count: 64)
            pkt[0] = 8; pkt[4] = UInt8(ident >> 8); pkt[5] = UInt8(ident & 0xff)
            pkt[6] = UInt8(seq >> 8); pkt[7] = UInt8(seq & 0xff)
            for i in 8..<64 { pkt[i] = UInt8(truncatingIfNeeded: i) }
            let cs = Self.checksum(pkt)
            pkt[2] = UInt8(cs >> 8); pkt[3] = UInt8(cs & 0xff)

            lock.withLock { sendTimes[seq] = Self.now() }
            let sent = withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if sent < 0 { lock.withLock { sendTimes[seq] = 0 } }

            let snapshot = lock.withLock { rtts }
            progress(snapshot)
            // Fixed schedule: sleep until the next tick, not for `interval` after the last send.
            let target = start + UInt64(Double(seq + 1) * interval * 1e9)
            let remaining = Int64(target) - Int64(Self.now())
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining)) }
            if Task.isCancelled { break }
        }
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))   // let stragglers arrive
        let final = lock.withLock { rtts }
        progress(final)
        return final
    }
}
