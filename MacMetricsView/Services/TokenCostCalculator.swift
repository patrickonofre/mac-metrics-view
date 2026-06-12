import Foundation

/// Result of summing event costs over a window/scope (ADR-003). In-memory only,
/// derived per UI refresh — never persisted.
struct TokenCostBreakdown: Equatable {
    /// Sum of priced event costs in USD. Never negative or NaN.
    let totalUSD: Double
    /// Per-model USD attribution keyed by raw model id, largest cost first.
    let perModelUSD: [PerModelCost]
    /// Usage tokens (input + output + reasoning) of events whose model had no pricing
    /// entry. Excluded from `totalUSD`; the UI surfaces an indicator instead of
    /// silently under-reporting (ADR-003).
    let unpricedTokens: Int

    struct PerModelCost: Equatable {
        let model: String
        let usd: Double
    }

    static let zero = TokenCostBreakdown(totalUSD: 0, perModelUSD: [], unpricedTokens: 0)

    /// Combined-provider view: sums totals and merges per-model attribution,
    /// mirroring the `TokenAggregate` summation pattern (ADR-003).
    static func + (lhs: TokenCostBreakdown, rhs: TokenCostBreakdown) -> TokenCostBreakdown {
        var perModel: [String: Double] = [:]
        for entry in lhs.perModelUSD + rhs.perModelUSD {
            perModel[entry.model, default: 0] += entry.usd
        }
        return TokenCostBreakdown(
            totalUSD: lhs.totalUSD + rhs.totalUSD,
            perModelUSD: perModel
                .map { PerModelCost(model: $0.key, usd: $0.value) }
                .sorted { $0.usd > $1.usd },
            unpricedTokens: lhs.unpricedTokens + rhs.unpricedTokens
        )
    }
}

/// Pure per-event cost math over retained raw events (ADR-003): no UI, timers, or
/// filesystem. Cost = Σ input×rIn + output×rOut + reasoning×rOut + cacheRead×rRead +
/// cacheCreation×rWrite, rates from `TokenPricing` (ADR-002). Events whose model has
/// no pricing entry contribute zero and are counted in `unpricedTokens`.
enum TokenCostCalculator {

    static func cost(of events: [TokenUsageEvent]) -> TokenCostBreakdown {
        var perModel: [String: Double] = [:]
        var unpricedTokens = 0

        for event in events {
            guard let rates = TokenPricing.rates(for: event.model) else {
                unpricedTokens += max(0, event.inputTokens)
                    + max(0, event.outputTokens)
                    + max(0, event.reasoningTokens)
                continue
            }
            perModel[event.model, default: 0] += cost(of: event, rates: rates)
        }

        let total = perModel.values.reduce(0, +)
        return TokenCostBreakdown(
            totalUSD: total.isFinite ? max(0, total) : 0,
            perModelUSD: perModel
                .map { TokenCostBreakdown.PerModelCost(model: $0.key, usd: $0.value) }
                .sorted { $0.usd > $1.usd },
            unpricedTokens: unpricedTokens
        )
    }

    /// One event's USD cost. Reasoning bills at the output rate (ADR-002); negative
    /// counts (malformed logs) clamp to zero so the total can never go negative.
    private static func cost(of event: TokenUsageEvent, rates: TokenModelRates) -> Double {
        let perMTok = Double(max(0, event.inputTokens)) * rates.inputPerMTok
            + Double(max(0, event.outputTokens)) * rates.outputPerMTok
            + Double(max(0, event.reasoningTokens)) * rates.outputPerMTok
            + Double(max(0, event.cacheReadTokens)) * rates.cacheReadPerMTok
            + Double(max(0, event.cacheCreationTokens)) * rates.cacheWritePerMTok
        return perMTok / 1_000_000
    }
}
