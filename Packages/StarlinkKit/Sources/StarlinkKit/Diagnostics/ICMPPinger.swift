import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum PingError: Error, Sendable, LocalizedError {
    case socket(String)
    case badAddress(String)
    case invalidArguments
    case alreadyRunning
    public var errorDescription: String? {
        switch self {
        case .socket(let s): "Ping socket error: \(s)"
        case .badAddress(let a): "“\(a)” isn't an IPv4 address."
        case .invalidArguments: "Invalid ping count, interval, or timeout."
        case .alreadyRunning: "This ping test is already running."
        }
    }
}

/// Unprivileged ICMP echo on Darwin. Each run uses a connected socket and a random payload token.
/// A pinger may run one measurement at a time; cancellation throws rather than returning a partial run.
public final class ICMPPinger: @unchecked Sendable {
    private let lock = NSLock()
    private var sendTimes: [UInt64] = []
    private var rtts: [Double?] = []
    private var stop = false
    private var receiverError: String?
    private var running = false

    public init() {}
    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private static func join(_ group: DispatchGroup) async {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    /// Extracts a sequence only from an echo reply carrying this run's token.
    /// Darwin can supply an IPv4 header; accepting a bare ICMP packet also makes parsing explicit.
    static func replySequence(_ bytes: ArraySlice<UInt8>, token: [UInt8]) -> Int? {
        let packet = Array(bytes)
        guard let first = packet.first else { return nil }
        let offset: Int
        if first >> 4 == 4 {
            offset = Int(first & 0x0f) * 4
            guard offset >= 20 else { return nil }
        } else {
            offset = 0
        }
        guard token.count == 8, packet.count >= offset + 16,
              packet[offset] == 0, packet[offset + 1] == 0,
              Array(packet[(offset + 8)..<(offset + 16)]) == token else { return nil }
        return Int(UInt16(packet[offset + 6]) << 8 | UInt16(packet[offset + 7]))
    }

    /// Sends on a fixed clock. Progress contains only the probes already sent; nil means no reply yet.
    public func run(host: String, count: Int, interval: TimeInterval, timeout: TimeInterval = 1.0,
                    progress: @escaping @Sendable ([Double?]) -> Void) async throws -> [Double?] {
        guard (1...65_535).contains(count), interval.isFinite, interval > 0, interval <= 60,
              timeout.isFinite, timeout >= 0, timeout <= 60 else { throw PingError.invalidArguments }
        let admitted = lock.withLock { () -> Bool in
            guard !running else { return false }
            running = true
            return true
        }
        guard admitted else { throw PingError.alreadyRunning }
        defer { lock.withLock { running = false } }
        try Task.checkCancellation()

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { throw PingError.badAddress(host) }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { throw PingError.socket(String(cString: strerror(errno))) }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { throw PingError.socket(String(cString: strerror(errno))) }
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            throw PingError.socket(String(cString: strerror(errno)))
        }

        lock.withLock { sendTimes = Array(repeating: 0, count: count); rtts = Array(repeating: nil, count: count); stop = false; receiverError = nil }
        let token = (0..<8).map { _ in UInt8.random(in: 0...255) }
        let receiverDone = DispatchGroup()
        receiverDone.enter()
        let receiver = Thread { [self] in
            defer { receiverDone.leave() }
            var buf = [UInt8](repeating: 0, count: 2048)
            while !lock.withLock({ stop }) {
                let n = recv(fd, &buf, buf.count, 0)
                if n < 0 {
                    let code = errno
                    if code == EAGAIN || code == EWOULDBLOCK || code == EINTR { continue }
                    lock.withLock { receiverError = String(cString: strerror(code)) }
                    return
                }
                guard n > 0 else { continue }
                let t = Self.now()
                guard let seq = Self.replySequence(buf.prefix(Int(n)), token: token) else { continue }
                lock.withLock {
                    if seq < sendTimes.count, sendTimes[seq] != 0, t >= sendTimes[seq], rtts[seq] == nil {
                        rtts[seq] = Double(t - sendTimes[seq]) / 1e6
                    }
                }
            }
        }
        receiver.qualityOfService = .userInitiated
        receiver.start()
        // The socket is closed only after the receive thread has exited, including cancellation.
        do {
            let start = Self.now()
            for seq in 0..<count {
                try Task.checkCancellation()
                if let error = lock.withLock({ receiverError }) { throw PingError.socket(error) }
                var pkt = [UInt8](repeating: 0, count: 64)
                pkt[0] = 8
                pkt[6] = UInt8(seq >> 8); pkt[7] = UInt8(seq & 0xff)
                pkt.replaceSubrange(8..<16, with: token)
                for i in 16..<64 { pkt[i] = UInt8(truncatingIfNeeded: i) }
                let cs = Self.checksum(pkt)
                pkt[2] = UInt8(cs >> 8); pkt[3] = UInt8(cs & 0xff)
                lock.withLock { sendTimes[seq] = Self.now() }
                let sent = pkt.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
                guard sent == pkt.count else { throw PingError.socket(String(cString: strerror(errno))) }
                progress(lock.withLock { Array(rtts.prefix(seq + 1)) })
                if seq + 1 < count {
                    let target = start + UInt64(Double(seq + 1) * interval * 1e9)
                    let remaining = Int64(target) - Int64(Self.now())
                    if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining)) }
                }
            }
            if timeout > 0 { try await Task.sleep(nanoseconds: UInt64(timeout * 1e9)) }
            try Task.checkCancellation()
            lock.withLock { stop = true }
            await Self.join(receiverDone)
            let (final, error) = lock.withLock { (rtts, receiverError) }
            if let error { throw PingError.socket(error) }
            progress(final)
            return final
        } catch {
            lock.withLock { stop = true }
            await Self.join(receiverDone)
            throw error
        }
    }
}
