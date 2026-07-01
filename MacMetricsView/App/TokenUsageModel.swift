import Foundation
import Combine

/// Rate-limit estimate published to the popover in one value (Phase 3): the
/// active 5h block (or `nil` between blocks), the rolling-week figures from the
/// daily ledger, and the user-set budgets (0 = off, ADR-008). Always
/// Claude-scoped regardless of the provider picker (ADR-006).
struct TokenRateLimitSnapshot: Equatable {
    let block: TokenRateLimitBlock?
    let weeklyUsage: TokenAggregate
    let weeklyCostUSD: Double
    let sessionBudget: Int
    let weeklyBudget: Int
}

/// The token-relevant slice of `MetricDisplaySettings` (scope/window/provider/budgets),
/// pushed into the model whenever the user changes a token picker. The persisted source
/// of truth stays `MetricDisplaySettings`; this is a derived read-model so the token
/// logic does not reach back into the shared display struct.
struct TokenDisplaySelection: Equatable {
    var scope: TokenScope
    var window: TokenWindow
    var provider: TokenProviderSelection
    var sessionBudget: Int
    var weeklyBudget: Int
}

/// The Dev/AI pillar (TD-012): per-provider token stores, the derived aggregate/cost/
/// burn-rate/rate-limit surfaces, the daily ledger behind the weekly figure, and the
/// popover-open refresh timer (ADR-005). Extracted from `CPUState` (spec
/// `spec-cpustate-pillar-decouple`, task-001) as an independent, testable
/// `@MainActor ObservableObject`. Persistence keys are unchanged (still `CPUState.token…`)
/// so existing installs load without migration.
@MainActor
final class TokenUsageModel: ObservableObject {
    /// One bounded token event store + since-reset accumulator per provider (ADR-003).
    @Published private(set) var tokenStores: [TokenProvider: TokenUsageStore]
    /// Token breakdown for the selected provider + scope + window. For `combined` it is
    /// the sum of each provider's aggregate. Drives the menu bar and popover.
    @Published private(set) var aggregate: TokenAggregate = .zero
    /// Estimated USD cost over the same selection, or `nil` when no events fall in the
    /// window (ADR-003).
    @Published private(set) var cost: TokenCostBreakdown?
    /// Events backing per-model attribution and the cost figure, merged across the
    /// selected providers, newest first.
    @Published private(set) var filteredEvents: [TokenUsageEvent] = []
    /// Pace over the fixed trailing hour for the selected provider(s), or `nil` (ADR-004).
    @Published private(set) var burnRate: TokenBurnRateBreakdown?
    /// Claude rate-limit estimate (5h block + rolling week + budgets), or `nil` when there
    /// is no data at all (ADR-006/007/008).
    @Published private(set) var rateLimit: TokenRateLimitSnapshot?

    /// Current token picker selection (derived from `MetricDisplaySettings`, pushed via
    /// `apply(selection:)`). Used by `recompute` and the presentation surfaces.
    private(set) var selection: TokenDisplaySelection

    /// Per-day Claude usage + cost buckets behind the weekly rate-limit figure (ADR-007).
    private(set) var dailyLedger = TokenDailyLedger()
    /// Newest folded event timestamp; events at or before it are skipped on fold.
    private var ledgerWatermark: Date?

    private let userDefaults: UserDefaults
    /// Active only while the popover is open (ADR-005); each tick re-runs the recompute
    /// with a fresh `now` so the trailing-hour burn rate and rolling windows keep sliding.
    private var autoRefreshTimer: Timer?
    private let autoRefreshInterval: TimeInterval = 30

    private enum Keys {
        /// Legacy single reset key (pre-Codex). Migrated once into the Claude slot.
        static let legacyResetAt = "CPUState.tokenResetAt"
        static func resetAt(_ provider: TokenProvider) -> String {
            "CPUState.tokenResetAt.\(provider.rawValue)"
        }
        /// JSON-encoded `TokenDailyLedger` backing the weekly figure (ADR-007).
        static let dailyLedger = "CPUState.tokenDailyLedger.claude"
        /// Newest Claude event timestamp already folded into the ledger (ADR-007).
        static let ledgerWatermark = "CPUState.tokenLedgerWatermark.claude"
        /// One-shot guard for the historical backfill scan (ADR-007).
        static let ledgerBackfilled = "CPUState.tokenLedgerBackfilled.claude"
    }

    init(userDefaults: UserDefaults, selection: TokenDisplaySelection) {
        self.userDefaults = userDefaults
        self.selection = selection

        // Per-provider reset times. Migrate the legacy single key into the Claude slot
        // once (ADR-003), so an existing install's since-reset measurement carries over.
        let legacyResetAt = userDefaults.object(forKey: Keys.legacyResetAt) as? Date
        let storedClaudeResetAt = userDefaults.object(forKey: Keys.resetAt(.claude)) as? Date
        let claudeResetAt = storedClaudeResetAt ?? legacyResetAt ?? Date()
        let codexResetAt = (userDefaults.object(forKey: Keys.resetAt(.codex)) as? Date) ?? Date()
        tokenStores = [
            .claude: TokenUsageStore(resetAt: claudeResetAt),
            .codex: TokenUsageStore(resetAt: codexResetAt)
        ]
        if storedClaudeResetAt == nil, let legacyResetAt {
            userDefaults.set(legacyResetAt, forKey: Keys.resetAt(.claude))
            userDefaults.removeObject(forKey: Keys.legacyResetAt)
        }

        // Daily ledger restore (ADR-007). A missing or undecodable payload yields an empty
        // ledger — corruption degrades, never crashes.
        if let data = userDefaults.data(forKey: Keys.dailyLedger),
           let ledger = try? JSONDecoder().decode(TokenDailyLedger.self, from: data) {
            dailyLedger = ledger
        }
        ledgerWatermark = userDefaults.object(forKey: Keys.ledgerWatermark) as? Date
    }

    deinit {
        autoRefreshTimer?.invalidate()
    }

    // MARK: - Ingest

    /// Ingests a batch of parsed token events into the given provider's store and
    /// republishes the selected aggregate. Independent of menu-bar visibility.
    func update(provider: TokenProvider, with events: [TokenUsageEvent]) {
        guard !events.isEmpty else { return }
        for event in events {
            tokenStores[provider]?.append(event)
        }
        if provider == .claude {
            foldIntoDailyLedger(events)
        }
        recompute()
    }

    /// Claude-provider convenience used by the existing Claude sampler path and tests.
    func update(with events: [TokenUsageEvent]) {
        update(provider: .claude, with: events)
    }

    /// Folds a Claude ingest batch into the daily ledger (ADR-007): cost computed at
    /// ingest, prune to the rolling 8 days, one debounced write per batch. The watermark
    /// skips events already counted before a relaunch.
    private func foldIntoDailyLedger(_ events: [TokenUsageEvent]) {
        let calendar = Calendar.current
        var folded = false
        for event in events {
            if let watermark = ledgerWatermark, event.timestamp <= watermark { continue }
            dailyLedger.fold(
                event,
                costUSD: TokenCostCalculator.cost(of: [event]).totalUSD,
                calendar: calendar
            )
            folded = true
        }
        guard folded else { return }
        if let newest = events.map(\.timestamp).max() {
            ledgerWatermark = max(ledgerWatermark ?? .distantPast, newest)
        }
        dailyLedger.prune(now: Date(), calendar: calendar)
        persistDailyLedger()
    }

    /// One write per ingest batch / backfill merge — the ledger is ~8 small entries.
    private func persistDailyLedger() {
        if let data = try? JSONEncoder().encode(dailyLedger) {
            userDefaults.set(data, forKey: Keys.dailyLedger)
        }
        if let watermark = ledgerWatermark {
            userDefaults.set(watermark, forKey: Keys.ledgerWatermark)
        }
    }

    // MARK: - Selection & reset

    /// Pushes a new token picker selection (after the caller persisted it on
    /// `MetricDisplaySettings`) and republishes every token-derived surface.
    func apply(selection: TokenDisplaySelection) {
        self.selection = selection
        recompute()
    }

    /// Starts a fresh since-reset measurement for the selected provider(s) — both when
    /// `combined` is selected (ADR-003). Each provider's `resetAt` is persisted under its
    /// own key so it survives relaunch.
    func resetCounter(now: Date = Date()) {
        for provider in selection.provider.providers {
            tokenStores[provider]?.reset(now: now)
            userDefaults.set(now, forKey: Keys.resetAt(provider))
        }
        recompute()
    }

    // MARK: - Popover-open auto refresh (ADR-005)

    /// Recomputes immediately so the figures are fresh the moment the popover opens, then
    /// ticks every ~30s. Idempotent — a second `begin` refreshes but never stacks a timer.
    func beginAutoRefresh() {
        recompute()
        guard autoRefreshTimer == nil else { return }
        autoRefreshTimer = MainRunLoopTimer.repeating(every: autoRefreshInterval) { [weak self] in
            self?.autoRefreshTick()
        }
    }

    /// Stops the popover-open refresh. Safe without a matching `begin` (no-op).
    func endAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    /// One refresh tick: re-runs the recompute with a fresh (injectable) `now`. A no-op
    /// once `end` ran, so a late timer fire cannot recompute after the popover closed.
    func autoRefreshTick(now: Date = Date()) {
        guard autoRefreshTimer != nil else { return }
        recompute(now: now)
    }

    // MARK: - Recompute

    /// The aggregate for the selected provider, or the sum of both providers' aggregates
    /// for `combined` (each with its own MRU — ADR-003). The same pass filters each
    /// provider's events once and derives the cost breakdown from them. `now` is injectable
    /// so the auto-refresh tick can slide the windows in tests.
    private func recompute(now: Date = Date()) {
        var newAggregate = TokenAggregate.zero
        var newCost = TokenCostBreakdown.zero
        var events: [TokenUsageEvent] = []
        var rateEvents: [TokenUsageEvent] = []

        for provider in selection.provider.providers {
            guard let store = tokenStores[provider] else { continue }
            newAggregate = newAggregate + TokenWindowStats.aggregate(
                store: store,
                scope: selection.scope,
                window: selection.window,
                now: now
            )
            let filtered = TokenWindowStats.filteredEvents(
                store: store,
                scope: selection.scope,
                window: selection.window,
                now: now
            )
            events += filtered
            newCost = newCost + TokenCostCalculator.cost(of: filtered)
            // Burn rate reads the raw store, not the picker-filtered set: its window is the
            // fixed trailing hour regardless of scope/window (ADR-004).
            rateEvents += store.events
        }

        events.sort { $0.timestamp > $1.timestamp }   // newest first across providers
        filteredEvents = events
        aggregate = newAggregate
        cost = events.isEmpty ? nil : newCost
        burnRate = TokenBurnRate.compute(events: rateEvents, now: now)

        // Rate-limit snapshot: always the Claude store, regardless of the pickers
        // (ADR-006); weekly from the ledger; budgets from the selection.
        let block = TokenRateLimitWindow.activeBlock(
            events: tokenStores[.claude]?.events ?? [],
            now: now
        )
        let weekly = dailyLedger.weeklyTotal(now: now, calendar: .current)
        if block == nil, weekly.usage.total == 0, weekly.costUSD == 0 {
            rateLimit = nil
        } else {
            rateLimit = TokenRateLimitSnapshot(
                block: block,
                weeklyUsage: weekly.usage,
                weeklyCostUSD: weekly.costUSD,
                sessionBudget: selection.sessionBudget,
                weeklyBudget: selection.weeklyBudget
            )
        }
    }

    // MARK: - Presentation

    /// Token volume has no danger threshold in the volume-only MVP — always `.normal`.
    var menuBarTextStyle: CPUMenuBarTextStyle {
        TokenFormatter.menuBarTextStyle(for: aggregate)
    }

    /// Whether the token meter has nothing meaningful to show (no logs / all-zero).
    var isEmpty: Bool {
        TokenFormatter.isEmpty(aggregate)
    }

    /// Headline value for the popover token row: the humanized total, or the localized
    /// empty/zero state when there is no data.
    var rowValue: String {
        isEmpty ? TokenFormatter.emptyState() : TokenFormatter.humanized(aggregate.usageTotal)
    }

    /// Localized input/output/cache breakdown rows for the popover.
    var breakdown: [(label: String, value: String)] {
        TokenFormatter.breakdown(for: aggregate)
    }

    /// Formatted estimated-cost headline for the popover cost row, or `nil` when there is
    /// no cost to show — the row hides instead of rendering a misleading `$0.00`.
    var costRowValue: String? {
        cost.map { TokenFormatter.costString($0.totalUSD) }
    }

    /// Per-model formatted costs for the attribution list, largest first.
    var costPerModel: [(label: String, value: String)] {
        guard let cost else { return [] }
        return cost.perModelUSD.map { entry in
            (TokenFormatter.modelDisplayName(entry.model) ?? entry.model,
             TokenFormatter.costString(entry.usd))
        }
    }

    /// Whether the unpriced indicator must accompany the cost figure (ADR-003).
    var costHasUnpricedTokens: Bool {
        (cost?.unpricedTokens ?? 0) > 0
    }

    /// Formatted pace line for the popover, or `nil` when no event falls in the trailing
    /// hour — the row hides instead of rendering a misleading zero pace (ADR-004).
    var paceRowValue: String? {
        burnRate.map { TokenFormatter.burnRateString($0) }
    }

    /// Distinct friendly model names used within the current provider/scope/window, newest
    /// first. `nil` when there is no usage to attribute.
    var activeModels: String? {
        guard !isEmpty else { return nil }
        var seen = Set<String>()
        let names = filteredEvents.compactMap { event -> String? in
            guard !seen.contains(event.model) else { return nil }
            seen.insert(event.model)
            return TokenFormatter.modelDisplayName(event.model)
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Sparkline values (0–100 normalized) of recent token volume for the selected
    /// provider/scope/window. For `combined`, per-bucket totals are summed across providers
    /// before normalizing. Empty when there is no data.
    var sparkline: [Double] {
        guard !isEmpty else { return [] }
        let now = Date()
        var summed: [Int] = []
        for provider in selection.provider.providers {
            guard let store = tokenStores[provider] else { continue }
            let buckets = TokenWindowStats.sparklineBuckets(
                store: store,
                scope: selection.scope,
                window: selection.window,
                now: now
            )
            if summed.isEmpty {
                summed = buckets
            } else {
                for index in buckets.indices where index < summed.count {
                    summed[index] += buckets[index]
                }
            }
        }
        guard let peak = summed.max(), peak > 0 else { return [] }
        return summed.map { Double($0) / Double(peak) * 100 }
    }
}
