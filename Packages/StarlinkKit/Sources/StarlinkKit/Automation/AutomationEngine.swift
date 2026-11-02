import Foundation

/// Evaluates `AlertRule`s against every polled sample, with a sustained-duration debounce (so a blip doesn't
/// fire) and a cooldown (so one ongoing problem fires once, not every poll, until it clears). Pure logic —
/// no `UNUserNotificationCenter` here; the app layer turns a returned `TriggeredAlert` into a system
/// notification. Rules and fired history persist as plain JSON, same hygiene as `ResultsStore`/`HistoryStore`.
public actor AutomationEngine {
    private let rulesURL: URL
    private let firedURL: URL

    public private(set) var rules: [AlertRule]
    public private(set) var fired: [TriggeredAlert] = []
    public private(set) var persistenceError: String?
    private var blockedByLoadFailure = false

    private var breachStart: [UUID: Date] = [:]      // rule id -> when the condition first became true
    private var firedSinceClear: Set<UUID> = []       // rule ids already fired for the current, still-ongoing breach

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Perigee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        rulesURL = dir.appendingPathComponent("alert-rules.json")
        firedURL = dir.appendingPathComponent("alert-history.json")

        var loadError: String?
        if let loaded: [AlertRule] = Self.load(from: rulesURL, error: &loadError) { rules = loaded } else { rules = AlertRule.defaults() }
        fired = Self.load(from: firedURL, error: &loadError) ?? []
        if let loadError {
            blockedByLoadFailure = true
            persistenceError = loadError
        }
    }

    private static func load<T: Decodable>(from url: URL, error outError: inout String?) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder.iso.decode(T.self, from: Data(contentsOf: url))
        } catch {
            outError = "Existing alert data could not be read; the files were left untouched."
            return nil
        }
    }

    public func setRules(_ newRules: [AlertRule]) {
        rules = newRules
        let ids = Set(newRules.map(\.id))
        breachStart = breachStart.filter { ids.contains($0.key) }
        firedSinceClear = firedSinceClear.filter { ids.contains($0) }
        persist()
    }

    /// Evaluate one sample against every enabled rule. Returns only the alerts that just crossed from "ok" to
    /// "fired" (sustained long enough, not already firing) — the caller shows/notifies only those.
    @discardableResult
    public func evaluate(_ sample: HistorySample, now: Date = Date()) -> [TriggeredAlert] {
        var newlyFired: [TriggeredAlert] = []
        for rule in rules where rule.enabled {
            guard let value = rule.metric.value(in: sample) else { continue }
            let breached = rule.condition.breached(value, threshold: rule.threshold)
            guard breached else {
                breachStart[rule.id] = nil
                firedSinceClear.remove(rule.id)
                continue
            }
            let start = breachStart[rule.id] ?? now
            breachStart[rule.id] = start
            guard now.timeIntervalSince(start) >= rule.sustainedFor, !firedSinceClear.contains(rule.id) else { continue }
            let alert = TriggeredAlert(ruleId: rule.id, date: now, title: rule.title, message: message(for: rule, value: value))
            fired.insert(alert, at: 0)
            if fired.count > 200 { fired.removeLast() }
            firedSinceClear.insert(rule.id)
            newlyFired.append(alert)
        }
        if !newlyFired.isEmpty { persist() }
        return newlyFired
    }

    private func message(for rule: AlertRule, value: Double) -> String {
        switch rule.metric {
        case .routerOffline, .dishOffline: "Not answering for at least \(Int(rule.sustainedFor))s."
        case .ping: String(format: "%.0f ms, above your %.0f ms threshold.", value, rule.threshold)
        default: String(format: "%.1f%%, above your %.1f%% threshold.", value * 100, rule.threshold * 100)
        }
    }

    public func clearFiredHistory() { fired = []; persist() }

    private func persist() {
        guard !blockedByLoadFailure else { return }
        do {
            try JSONEncoder.iso.encode(rules).write(to: rulesURL, options: .atomic)
            try JSONEncoder.iso.encode(fired).write(to: firedURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

extension AutomationEngine {
    /// Live data persists under `siteDirectory` (or the app's default location when `nil`); demo data gets its
    /// own throwaway directory per launch, matching `HistoryStore.makeDefault(for:)`.
    public static func makeDefault(for source: DataSource, siteDirectory: URL? = nil) -> AutomationEngine {
        switch source {
        case .live:
            return AutomationEngine(directory: siteDirectory)
        case .demo:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PerigeeDemoAlerts-\(UUID().uuidString)", isDirectory: true)
            return AutomationEngine(directory: dir)
        }
    }
}
