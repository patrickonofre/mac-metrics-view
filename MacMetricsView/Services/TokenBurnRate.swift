import Foundation

/// Pace over the trailing hour (ADR-004). In-memory, derived per recompute —
/// never persisted.
struct TokenBurnRateBreakdown: Equatable {
    /// Usage tokens (input + output + reasoning) per hour. Never negative or NaN.
    let tokensPerHour: Double
    /// USD cost of the window's events per hour, via `TokenCostCalculator` (ADR-003).
    let costPerHourUSD: Double
    /// Daily-cost projection: `costPerHourUSD × 24` (ADR-004).
    let costPerDayUSD: Double
}

/// Pure burn-rate math over retained raw events (ADR-004): no timers, filesystem, or
/// mutable state. Sibling of `TokenCostCalculator`. The window is a fixed 60 minutes
/// ending at the injected `now`, independent of the scope/window pickers — the figure
/// always answers "pace over the last hour".
enum TokenBurnRate {
    static let window: TimeInterval = 3_600

    /// `nil` when no event falls in `[now − window, now]` — the UI row hides
    /// (ADR-004). A single in-window event computes normally; the fixed 1h
    /// denominator already spreads lone bursts, so there is no minimum-history
    /// threshold.
    static func compute(events: [TokenUsageEvent], now: Date) -> TokenBurnRateBreakdown? {
        let start = now.addingTimeInterval(-window)
        let inWindow = events.filter { $0.timestamp >= start && $0.timestamp <= now }
        guard !inWindow.isEmpty else { return nil }

        // Same figure as `TokenAggregate.usageTotal` (cache excluded); negative
        // counts from malformed logs clamp to zero so the rate can never go negative.
        let usageTokens = inWindow.reduce(0) {
            $0 + max(0, $1.inputTokens) + max(0, $1.outputTokens) + max(0, $1.reasoningTokens)
        }
        let hours = window / 3_600
        let tokensPerHour = Double(usageTokens) / hours
        let costPerHour = TokenCostCalculator.cost(of: inWindow).totalUSD / hours

        return TokenBurnRateBreakdown(
            tokensPerHour: tokensPerHour.isFinite ? max(0, tokensPerHour) : 0,
            costPerHourUSD: costPerHour.isFinite ? max(0, costPerHour) : 0,
            costPerDayUSD: costPerHour.isFinite ? max(0, costPerHour * 24) : 0
        )
    }
}
