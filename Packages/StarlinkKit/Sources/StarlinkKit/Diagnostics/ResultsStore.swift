import Foundation

/// Saved stall-test runs for A/B comparison. Plain JSON in Application Support; no network, no analytics.
public actor ResultsStore {
    private let url: URL
    public private(set) var results: [StallResult] = []
    public private(set) var persistenceError: String?
    private var blockedByLoadFailure = false

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("stall-results.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                results = try JSONDecoder.iso.decode([StallResult].self, from: data)
            } catch {
                blockedByLoadFailure = true
                persistenceError = "Existing results could not be read; the file was left untouched."
            }
        }
    }

    public func add(_ r: StallResult) { results.insert(r, at: 0); if results.count > 200 { results.removeLast() }; persist() }
    public func remove(_ id: UUID) { results.removeAll { $0.id == id }; persist() }
    public func removeAll() { results = []; persist() }
    public func rename(_ id: UUID, to label: String) {
        if let i = results.firstIndex(where: { $0.id == id }) { results[i].label = label; persist() }
    }

    private func persist() {
        guard !blockedByLoadFailure else { return }
        do {
            let data = try JSONEncoder.iso.encode(results)
            try data.write(to: url, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
