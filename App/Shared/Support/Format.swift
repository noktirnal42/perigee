import Foundation

enum Fmt {
    static func ms(_ v: Double?) -> String { v.map { $0 < 10 ? String(format: "%.1f", $0) : String(Int($0.rounded())) } ?? "—" }
    static func percent(_ v: Double?, digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0 * 100) } ?? "—" }
    static func rate(_ bps: Double) -> (String, String) {
        let m = bps / 1e6
        if m >= 100 { return (String(Int(m.rounded())), "Mbps") }
        if m >= 1 { return (String(format: "%.1f", m), "Mbps") }
        return (String(Int((bps / 1e3).rounded())), "kbps")
    }
    static func mbps(_ m: Double) -> String { m >= 10 ? String(Int(m.rounded())) : String(format: "%.1f", m) }
    static func uptime(_ s: TimeInterval) -> String {
        let d = Int(s) / 86400, h = Int(s) % 86400 / 3600, m = Int(s) % 3600 / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
    static func duration(_ s: Int) -> String { uptime(TimeInterval(s)) }
    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }
    static func mac(_ s: String) -> String { s.uppercased() }
    static func downsample(_ v: [Double?], to n: Int) -> [Double] {
        let vals = v.compactMap { $0 }
        guard vals.count > n, n > 0 else { return vals }
        let step = Double(vals.count) / Double(n)
        return (0..<n).map { i in
            let a = Int(Double(i) * step), b = min(vals.count, Int(Double(i + 1) * step))
            let slice = vals[a..<max(a + 1, b)]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}
