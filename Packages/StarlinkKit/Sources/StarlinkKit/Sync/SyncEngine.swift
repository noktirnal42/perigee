import Foundation
import Observation

/// Syncs saved sites between the user's own devices via CloudKit (SPEC_v2.md §4F). Strictly opt-in — `isEnabled`
/// starts `false` and nothing is read or written anywhere until the user turns it on. Scope for this pass:
/// the site list only (name, router/dish address) — saved stall-test history stays device-local, since it's
/// stored per-site-directory today and syncing it is a larger, separate piece of work (SPEC_v2.md §7e).
///
/// Merge rule: last-write-wins by `Site.updatedAt`, decided against `lastSyncDate` rather than a full snapshot
/// cache — anything changed locally after the last successful sync is "a pending local edit"; anything the
/// transport reports changed since the last pull token is "a pending remote change." A genuine concurrent edit
/// (both sides changed since the last sync) is resolved by comparing timestamps directly, and the loser is
/// silently overwritten next pass — the same honestly-simple tradeoff as any last-write-wins sync, not a CRDT.
@MainActor @Observable
public final class SyncEngine {
    public enum Status: Sendable, Equatable {
        case idle, syncing
        case succeeded(Date)
        case failed(String)
    }

    public private(set) var status: Status = .idle

    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { Task { await self.sync() } }
        }
    }

    private let siteStore: SiteStore
    private let transport: CloudSyncTransport?
    private let defaults: UserDefaults

    private var lastSyncDate: Date? {
        didSet { defaults.set(lastSyncDate, forKey: Self.lastSyncKey) }
    }
    private var token: SyncToken? {
        didSet { if let token { defaults.set(token.raw, forKey: Self.tokenKey) } }
    }

    private static let enabledKey = "Perigee.sync.enabled"
    private static let lastSyncKey = "Perigee.sync.lastSyncDate"
    private static let tokenKey = "Perigee.sync.token"

    /// - Parameter transport: `nil` means sync can never actually run (e.g. CloudKit unavailable on this
    ///   platform/build) — `isEnabled` can still be flipped in Settings, but `sync()` does nothing.
    public init(siteStore: SiteStore, transport: CloudSyncTransport?, defaults: UserDefaults = .standard) {
        self.siteStore = siteStore
        self.transport = transport
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        if let raw = defaults.data(forKey: Self.tokenKey) { self.token = SyncToken(raw: raw) }
    }

    private var inFlight: Task<Void, Never>?

    /// Runs one pull → merge → push pass. Safe to call repeatedly and from anywhere (app foreground, after a
    /// site edit, a manual "Sync now" button) — a no-op if sync is off or no transport is configured.
    ///
    /// `isEnabled`'s didSet fires an un-awaited sync Task, and the app layer calls this from several other
    /// independent places too, so overlapping calls are the normal case, not an edge case. A call that arrives
    /// while one is already running joins that same in-flight pass instead of starting a conflicting second one
    /// (which would race on `siteStore`/`lastSyncDate`/`token`) or silently dropping its own work as a no-op
    /// (which would make `await sync()` lie about having synced anything).
    public func sync() async {
        guard isEnabled, let transport else { return }
        if let inFlight {
            await inFlight.value
            return
        }
        // Clear `inFlight` as the task's own last step, not after awaiting it here — `.value` resolves for
        // every awaiter (this call and any joiner) at the same moment the closure finishes, so if the clear
        // happened out here instead, a `sync()` called right after this one returns could still find a
        // stale, already-finished task in `inFlight` and silently join it instead of running a fresh pass —
        // exactly the kind of "awaited sync() but nothing actually happened" bug this type exists to avoid.
        let task = Task {
            await self.runSync(transport: transport)
            self.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func runSync(transport: CloudSyncTransport) async {
        status = .syncing
        guard await transport.accountAvailable() else {
            status = .failed(SyncError.accountUnavailable.errorDescription ?? "")
            return
        }
        // `nil` means this device has never completed a sync — there's no meaningful "edited since last talked
        // to the server" signal yet, so remote state is trusted outright and every local site is pushed, rather
        // than treating every pre-existing local site as a fresher-than-`.distantPast` "concurrent edit".
        let cutoff = lastSyncDate
        do {
            let pulled = try await transport.pull(since: token)

            // Remote upserts: apply unless a local edit since the last sync is strictly newer, OR this device
            // already deleted the same site locally at least as recently as the upsert claims. The tombstone
            // check matters independently of token freshness: a transport can always hand back an upsert for
            // something this device has since deleted (another device hadn't caught up yet, or — as here —
            // this device's own earlier push comes back on the very next pull before the deletion follows it).
            // Applying it anyway would resurrect the site *and* erase the tombstone the push step below needs
            // to actually propagate the deletion.
            var locallyWonIDs: Set<String> = []
            for record in pulled.upserts where record.kind == .site {
                guard let remote = try? JSONDecoder.iso.decode(Site.self, from: record.payload) else { continue }
                if let tombstoneDate = siteStore.tombstones[remote.id], tombstoneDate >= remote.updatedAt {
                    continue
                }
                if let cutoff, let local = siteStore.sites.first(where: { $0.id == remote.id }),
                   local.updatedAt > cutoff, local.updatedAt > remote.updatedAt {
                    locallyWonIDs.insert(record.id)
                } else {
                    siteStore.applyRemoteUpsert(remote)
                }
            }

            // Remote deletions: apply unless the site was edited locally since the last sync (the edit wins,
            // the site survives and gets pushed back below — effectively "undeleting" it everywhere else too).
            for deletion in pulled.deletedIDs where deletion.kind == .site {
                guard let id = UUID(uuidString: deletion.id) else { continue }
                guard let local = siteStore.sites.first(where: { $0.id == id }) else { continue }
                if let cutoff, local.updatedAt > cutoff { continue }
                siteStore.applyRemoteDeletion(id, at: Date())
            }

            // Push: on a first-ever sync, everything local (nothing to compare a cutoff against); otherwise
            // anything changed locally since the last sync, plus anything that just won a conflict above.
            let toPush = siteStore.sites.filter { site in
                guard let cutoff else { return true }
                return site.updatedAt > cutoff || locallyWonIDs.contains(site.id.uuidString)
            }
            let upserts = try toPush.map { site in
                SyncRecord(kind: .site, id: site.id.uuidString, updatedAt: site.updatedAt, payload: try JSONEncoder.iso.encode(site))
            }
            let deletions = siteStore.tombstones
                .filter { cutoff == nil || $0.value > cutoff! }
                .map { (kind: SyncKind.site, id: $0.key.uuidString) }
            if !upserts.isEmpty || !deletions.isEmpty {
                try await transport.push(upserts: upserts, deletions: deletions)
            }

            token = pulled.token
            let now = Date()
            lastSyncDate = now
            status = .succeeded(now)
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
