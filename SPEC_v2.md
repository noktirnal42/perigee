# Perigee v2.0 — Product Spec & Roadmap

Status: **draft for review**. Nothing here is implemented yet. This document is the result of (a) researching the existing Starlink-tooling landscape and (b) auditing Perigee v1's feature set against it, to define a v2.0 that is a clear step-change rather than incremental polish.

---

## 1. Competitive landscape (research summary)

**Official Starlink app** — 4.9★/114K ratings. Covers account/billing, obstruction check, basic signal %, install guidance. It is the only way to do initial setup and pay the bill. It has no tuning, no history beyond "now," and is a walled garden by design — it will never expose channel/DFS/CAKE controls or let you see raw telemetry.

**Community CLI/scripting tools** (the real prior art for "see everything"):
- [sparky8512/starlink-grpc-tools](https://github.com/sparky8512/starlink-grpc-tools) — the de facto reference implementation for the local gRPC API. Python scripts that poll status/history/alerts and can feed InfluxDB or Prometheus. Ships a Grafana dashboard JSON. This is what self-hosters actually run today.
- [clarkzjw/starlink_exporter](https://pkg.go.dev/github.com/clarkzjw/starlink_exporter) — Prometheus exporter, Go, GPL-3.0.
- [faeton/dishwatch](https://github.com/faeton/dishwatch) — a terminal dashboard (signal/aim/GPS/power, ping+drop graphs, reboot/raw-request commands). Closest thing to a "nice UI" in this space, and it's a TUI.
- [lgqiao/starlink-1](https://github.com/lgqiao/starlink-1) — Docker Compose stack bundling Prometheus/Grafana/exporters/speedtest.
- [starlink-community/starlink-cli](https://github.com/starlink-community/starlink-cli), danfedick/starlink-cli — basic Go/Rust CLIs for status/stow/reboot/GPS.

Common thread: **powerful raw data, zero UX, zero safety model, zero mobile story.** Every one of these requires a server, Docker, InfluxDB/Prometheus, and command-line comfort. None of them run on a phone. None of them gate writes. None of them visualize the constellation. This is exactly the gap Perigee v1 already exploits — v2 should widen that lead specifically in the area these tools are strongest at: **long-term history and trends**, which Perigee v1 currently does *not* have (it only sees the device's live 15-minute buffer, plus whatever stall-test runs the user manually saved).

**Consumer mesh-router apps** (eero, UniFi) — good UX reference, not Starlink-specific:
- eero's app is four tabs (Home/Devices/Activity/Settings); Activity shows a recent speed-test result, not a history trend.
- UniFi's app/controller has materially more depth (VLANs, traffic shaping) but at the cost of complexity; no public info found on long-term speed-test history or a rule-based automation UI in either.
- Neither has anything resembling an obstruction map, satellite visibility, or a safety-gated write model — that remains Perigee's unique territory.

**2026 market shift relevant to this app**: Starlink has been actively changing data-cap/Priority-Access rules this year (Roam plans moved to 100GB caps with notification at 80%/100%, a 10 Mbps speed cap was introduced for heavy "unlimited" users, Priority data can be topped up at $0.25/GB during peak hours 7am–11pm). Users increasingly need to **track usage against a cap**, which nothing in this space (including Perigee v1) currently helps with on-device.

Sources: [starlink-grpc-tools](https://github.com/sparky8512/starlink-grpc-tools) · [starlink_exporter](https://pkg.go.dev/github.com/clarkzjw/starlink_exporter) · [dishwatch](https://github.com/faeton/dishwatch) · [starlink-1](https://github.com/lgqiao/starlink-1) · [starlink-cli](https://github.com/starlink-community/starlink-cli) · [ISPreview: Priority Access & speed cap](https://www.ispreview.co.uk/index.php/2026/09/starlink-impose-10mbps-speed-cap-on-heavy-users-of-its-unlimited-broadband.html) · [Roam 100GB change](https://www.notebookcheck.net/Starlink-intros-100-GB-Roam-plan-with-free-unlimited-low-speed-data.1204378.0.html) · [eero app tabs](https://eero.com/support/articles/what-features-are-in-the-eero-app)

---

## 2. Gaps in Perigee v1 (self-audit)

1. **No persistent history.** Device buffers 15 minutes; Perigee only keeps what the user manually saves from the stall tester. No uptime %, no obstruction trend, no "what did last Tuesday look like."
2. **No alerts/automation.** Perigee is 100% pull — you only learn something's wrong by opening the app.
3. **No widgets, Live Activity, Apple Watch, or Siri Shortcuts / App Intents.**
4. **No data-usage / plan-cap awareness**, despite this becoming a real pain point in 2026 Starlink plans.
5. **No multi-site / fleet support** — one router+dish only, no profile for a second property, RV/Roam dish, or boat.
6. **No predictive signal.** Obstruction map and satellite view are both presented live/retrospectively, never as a forecast ("risk window coming up").
7. **Tuning is a set of separate screens**, not a guided loop; there's no annotated timeline tying a specific change to its measured before/after effect over the following hours.
8. **Visual design is v1-era**: custom procedural art + plain SwiftUI. No Liquid Glass adoption, limited motion/haptics, no AR, no localization scaffolding, iPad still uses an adapted-phone layout rather than true multi-pane.
9. **No sync** — presets, saved stall runs and sites live on one device only.

---

## 3. v2.0 vision

> v1 answers **"what is my network doing right now."** v2.0 answers **"what has it been doing, what's about to happen, and tell me the moment something's wrong"** — without ever adding a server, an account, or a byte of telemetry.

"5x better" is defined concretely in §7, not as a slogan.

---

## 4. Feature pillars

### A. History & Trends Engine — *the foundation, build first*
New `StarlinkKit/History` module.
- On-device time-series store (SQLite/GRDB): snapshot every poll, rolled up to 1-min / 1-hour / 1-day buckets. Configurable retention (7/30/90 days, unlimited on Mac).
- Trend charts (Swift Charts, Health-app-style scrubbing): uptime %, obstruction %, ping p50/p95, stall count, per-band frame-error rate, signal — over any custom range.
- **Timeline annotations**: every verified tuning write and every stall-test run becomes a marker on the trend chart, so "did that channel change actually help?" has a real, multi-day answer instead of a single A/B run.
- CSV/JSON export for the power users who currently reach for self-hosted Grafana — Perigee becomes a replacement for that stack, not just a nicer front end to live status.

### B. Alerts & Automation
New `StarlinkKit/Automation` module. Local notifications only — no push server.
- Built-in alerts: dish/router offline, obstruction spike, stall-tester threshold breach, firmware/update window starting, data-usage threshold crossed.
- Simple rule builder: `if <metric> <condition> for <duration> → notify / start recording`.
- "Weekly recap" local notification: uptime, obstruction trend, best/worst hour.
- iOS uses BGTaskScheduler within Apple's background-execution limits (documented honestly — iOS will not poll every second while backgrounded); the Mac app's existing menu-bar poller becomes the reliable "always-on" collector, with iOS/iPad showing synced history rather than relying on its own background polling.

### C. Predictive Outage Forecast (new, distinctive)
New `StarlinkKit/Forecast` module.
- Combines the existing SGP4 constellation engine + obstruction map + historical stall correlation into a heuristic "elevated risk window" (e.g. "low satellite density over your obstructed sector, 6:40–6:52pm").
- Explicitly labeled as an estimate — same honesty standard already established for "connected satellite is an inference," never presented as a Starlink-published fact.
- Surfaces as a Home card and an optional pre-emptive notification ("rough 10 minutes coming up around dinner").

### D. Data & Plan Awareness
- User enters their plan type/cap/reset date manually (gRPC exposes no billing data, and Perigee will not attempt to read Starlink account/billing systems — out of scope by the existing safety policy).
- If the router/dish schema exposes any byte counters, reconcile them into a local usage gauge + linear projection ("at this rate, you'll hit 1TB by the 24th"). If not available, this becomes a manual log instead — never fabricated data.

### E. Multi-Site / Fleet Mode
- Multiple saved endpoints (home, second property, RV/Roam dish) with a quick switcher; per-site history, presets and tuning profiles.
- Directly motivated by Starlink's own 2026 push into Mini/Roam — users increasingly have more than one dish.

### F. Sync
- Optional CloudKit sync (Apple's own, private database, end-to-end between the user's own devices) for saved sites, presets, stall-test history and exported plans. Strictly opt-in; off by default; never a Perigee-run backend — keeps the "no account, no telemetry" promise.

### G. Widgets, Live Activity, Watch, Shortcuts
- Home/Lock Screen widgets: status, ping, obstruction %, next forecasted risk window.
- Live Activity during an active stall test or tuning A/B session.
- watchOS glance app (status/ping/alerts, read-only).
- App Intents for Siri/Shortcuts: "Is Starlink down?", "Run a stall test," "Switch to Gaming preset" — composable in the Shortcuts app, including Wi-Fi-join automations.

### H. Tuning UX 2.0
- Guided "Tuning Session" wizard replacing separate screens: baseline capture → change → compare → keep/revert, with the before/after chart overlaid inline.
- Advisor becomes history-aware: "Your 5GHz has had 3 DFS radar events this week — pin channel 36?" instead of static presets only.

### I. Visual & interaction design v2 — the "5x" UI bar
- Adopt Liquid Glass (iOS 26+/macOS 26 Tahoe): glass toolbars, `GlassEffectContainer` for Home's dashboard cards, tab-bar minimize behavior — with the existing pre-26 Material look kept as a fallback, never a regression for anyone not yet updated.
- Motion & haptics: shared-element transitions between Home ↔ Diagnose ↔ Sky, haptic feedback on verified-write success/revert, the obstruction map painting live rather than appearing instantly.
- Satellite globe v2: tap a satellite for name/NORAD ID/next pass, a time-scrubber to watch the constellation move, AR sky view (point the phone up, see an overlay of what's actually overhead) as a clearly-marked stretch goal.
- Full accessibility pass on the new charts (VoiceOver data-table/audio-graph fallback, not just Dynamic Type), localization scaffolding (strings catalog, number/unit formatting) even if only English ships first.
- True iPad multi-pane (sidebar + content + inspector) instead of a stretched-phone layout; richer Mac menu-bar extra (mini sparkline, right-click quick actions).

### J. Safety model — unchanged, non-negotiable
Every v1 guarantee carries forward exactly as-is: read-only by default, single-field verified writes, the in-code forbidden-method allowlist, destructive-action confirmation gating, mock-only write testing, PermissionDenied → view-only handling, and the standing rule that Perigee never decompiles or reverse-engineers the official Starlink app. The new History/Automation/Forecast/Sync modules add **zero new network egress** beyond the user's own devices (CloudKit, if opted into, is Apple's infrastructure between the user's own devices only) — no telemetry is introduced anywhere in v2.0.

---

## 5. Phased roadmap

| Phase | Scope | Why this order |
|---|---|---|
| 1 ✅ *(shipped)* | History engine + trend charts + timeline annotations | Everything else (alerts, forecast, weekly recap) needs data to act on |
| 2 ✅ *(shipped)* | Alerts/automation + weekly recap | Highest user-visible "it told me before I noticed" value |
| 3 ⚠️ *(partially shipped)* | Widgets + Shortcuts/App Intents shipped; Live Activity and watchOS deferred (see below) | High visibility, mostly additive UI work once History exists |
| 4 ⚠️ *(partially shipped)* | Multi-site/fleet shipped; CloudKit sync deferred (its own entitlement/container/conflict-resolution scope) | Needed before data model gets harder to migrate later |
| 5 ⚠️ *(partially shipped)* | Forecast engine shipped; history-aware Advisor tip added to the existing recommendations list; guided Tuning Session wizard deferred (see below) | Builds directly on History + multi-site data |
| 6 ⚠️ *(partially shipped)* | Liquid Glass correctness/consistency pass across the whole app shipped; globe v2, AR stretch, localization scaffolding and a deeper accessibility pass deferred (see below) | Polish pass once feature surface is settled |

---

## 6. Architecture changes

- New StarlinkKit targets, each protocol-based and mock-testable exactly like existing services: `History`, `Automation`, `Forecast`, `Sync`.
- Persistence: SQLite via GRDB for the time-series store (lightweight rollup queries, cross-platform, avoids Core Data's overhead for what's essentially an append-only log).
- Background execution: a shared `PollingDaemon` actor generalizing the existing Mac menu-bar poller; iOS hooks in via BGTaskScheduler within platform limits.
- New target types: WidgetKit extension(s), a watchOS app target, App Intents definitions — added to `project.yml` / XcodeGen alongside the existing `Perigee_iOS` / `Perigee_macOS` targets.
- No new third-party network dependencies. CloudKit is the only new "cloud" touchpoint, and it is Apple's, private-database, user-owned.

---

## 7. What "5x better" means, concretely

| | v1 | v2.0 |
|---|---|---|
| History | Device's live 15 min + manually saved stall runs | Unlimited (Mac) / 90-day (iOS) trend history with annotated timeline |
| Awareness | You open the app to find out | Local alerts + weekly recap push to you |
| Forecasting | None | Heuristic risk-window forecast from orbital + obstruction + stall data |
| Data cap | Not tracked | Local usage gauge + projection against your plan |
| Sites | One dish/router | Multiple saved sites with per-site history/presets |
| Devices | iPhone/iPad/Mac only, pull-based | + Widgets, Live Activity, Watch, Shortcuts — ambient and voice-driven |
| Tuning loop | Manual screens + one-off A/B | Guided wizard + history-aware Advisor + persistent before/after proof |
| Visual design | v1 procedural art, standard SwiftUI | Liquid Glass, motion/haptics, satellite globe v2 (+AR stretch) |
| Sync | None | Opt-in CloudKit across the user's own devices |
| Safety | Full v1 model | Identical guarantees, extended to every new module, zero new egress |

---

## 7a. Phase 3 scope note

Shipped: a `StatusSnapshot`/`SnapshotStore` bridge (StarlinkKit writes a small JSON snapshot to the app's
App Group container on every poll), an iOS Home/Lock Screen widget (`PerigeeWidgetsExtension`, small/medium +
accessory circular/rectangular) that reads it headlessly, and three App Intents/Shortcuts: a fully headless
"Is Starlink online?" status check, and "Run a stall test" / "Open Wi-Fi tuning" intents that open the app to
the right screen rather than acting themselves — consistent with the safety model's "every write is explicit."

Deliberately **not** built this pass: a macOS widget (iOS only for now), Live Activity for an in-progress stall
test, and a watchOS app. Live Activity and watchOS are real additional scope (new entitlements/targets and, for
watchOS, a full new platform target) better taken as their own pass rather than folded into this one.

## 7b. Phase 4 scope note

Shipped: `Site`/`SiteStore` — multiple saved installations (home, a second property, an RV/Roam dish, a boat),
each with its own router/dish address, history, alert rules and saved stall tests. The very first site a user
had before this feature shipped keeps using the app's original, un-scoped storage location (`isLegacyDefault`)
so nothing from Phases 1–3 is orphaned; every other site gets its own `Sites/<uuid>/` folder. Settings has a
new Sites section to switch, add, edit and delete sites. Site switching only applies to live data — demo mode
stays a single pseudo-site, unaffected.

Deliberately **not** built this pass: CloudKit sync. That's a distinct, larger piece of work (CloudKit
entitlement/container, `CKRecord` mapping for sites/presets/history, conflict resolution for multi-device
edits) better taken as its own pass; noted in SPEC_v2.md for a future phase.

## 7c. Phase 5 scope note

Shipped: a `StarlinkKit/Forecast` module (`RiskWindow`, `Forecast.windows(...)`) combining two independent
signals into a Home-screen "possible rough window ahead" card — (1) a satellite-density dip over the next 3
hours from the existing SGP4 constellation engine + saved observer location (the same `Observer` the Sky tab
already persists), and (2) hours of day that this device's own on-device history (`HistoryBucket`s, Phase 1)
has consistently run worse than its own average. Both signals require real data to say anything — no observer
location yet, or fewer than 24 hourly history buckets, and the card simply stays hidden rather than guessing.
Also shipped: `Advisor.historyAdvice(recentBuckets:tuning:)`, a second history-aware tip on the Tune screen
that compares the last ~3.5 days of hourly history against the previous ~3.5 days and flags a real upward
trend in obstruction or 5GHz frame errors — distinct from the existing live-snapshot advice, and silent with
fewer than 4 buckets.

Deliberately **not** built this pass: the guided "Tuning Session" wizard (baseline capture → change → compare
→ keep/revert with an inline before/after chart) described in §4H. Only the history-aware *tip* was added to
the existing Tune recommendations list; the wizard is a separate, larger UI flow better taken as its own pass.

## 7d. Phase 6 scope note

Perigee's card surfaces (`CardBackground`/`.card()`) already rendered as real Liquid Glass on iOS 26 /
macOS 26, with a Reduce-Transparency and pre-26-material fallback, from earlier work — this phase is a
correctness and consistency pass on top of that baseline, not a first adoption.

Shipped: every screen built from several stacked `.card()` surfaces (Home's dashboard, Network, Tune,
Dish/Satellites, Diagnostics and its Compare/Speed-and-trace sub-screens, Trends, and the Tune change
sheets — choice/CAKE/preset) now wraps its cards in one shared `GlassEffectContainer` (`.cardGroup()`
in `Surfaces.swift`), so neighbouring cards with different tints sample the backdrop consistently
instead of each opening its own region — glass cannot sample glass. `spacing: 0` deliberately opts out
of merging: these are a screen's worth of distinct cards, not a toolbar cluster meant to fuse into one
shape. Cards that are themselves a single tappable control (Home's network/gaming-check cards and
Settings button, Tune's preset cards, the globe's "Center on me" control) now pass `interactive: true`
so the glass itself reacts to touch/pointer; static multi-row list cards were left non-interactive on
purpose, since `interactive()` installs continuous gesture tracking that's pure cost on an inert
surface. The iOS tab bar now sets `tabBarMinimizeBehavior(.onScrollDown)`. Toolbars, sheets and the
Mac sidebar take system glass for free on recompile and needed no code change.

Deliberately **not** built this pass: satellite globe v2 (tap-for-info, time-scrubber, AR stretch
goal), localization scaffolding, a deeper accessibility pass on the trend charts specifically
(VoiceOver audio-graph/data-table fallback beyond the Dynamic Type and Reduce Transparency/Motion
support already in place), a true iPad inspector-pane layout beyond the existing `.sidebarAdaptable`
tab styling, and a richer Mac menu-bar extra (mini sparkline, right-click quick actions). Each is real
additional scope — new interaction design, new data wiring, or a new platform-specific layout — better
taken as its own pass.

## 8. Open questions for you

1. CloudKit sync — want it in scope for v2, or keep every device fully independent?
2. watchOS — worth building given the dish/router are LAN-bound (so the Watch would need the phone nearby anyway), or cut?
3. AR sky view — keep as a stretch goal, or drop it now to focus the roadmap?
4. Does the phase order in §5 match your priorities, or would you rather pull Alerts (Phase 2) or Widgets/Shortcuts (Phase 3) ahead of the History engine's full build-out?
