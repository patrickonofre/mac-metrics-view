import Foundation

/// Formats a `TokenAggregate` into menu bar and popover strings. Token volume has no
/// danger threshold in the volume-only MVP, so it always renders `.normal` (ADR-003).
enum TokenFormatter {
    /// Short, non-localized menu bar identifier, matching the `CPU` / `DISK` style. Used
    /// when no provider context is available; the provider-aware UI uses
    /// `menuBarLabel(for:language:)` instead.
    static let menuBarLabel = "TOK"

    /// Provider-aware menu bar identifier, replacing the fixed `TOK` so the single number
    /// reads as Claude, Codex, or Combined (ADR-001). Sourced from the localized provider
    /// names (Task 10).
    static func menuBarLabel(
        for selection: TokenProviderSelection,
        language: AppLanguage = .current
    ) -> String {
        Strings.tokenProviderName(selection)(language)
    }

    /// Compact humanized count: `950`, `1.5k`, `2.3M`. One decimal for k/M keeps the
    /// width roughly stable across magnitudes.
    static func humanized(_ count: Int) -> String {
        let value = max(0, count)

        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// Menu bar segment for the selected window's aggregate. `nil` data shows a neutral
    /// placeholder rather than a misleading zero.
    static func menuBarTitle(for aggregate: TokenAggregate?, showLabel: Bool = true) -> String {
        let value = aggregate.map { humanized($0.usageTotal) } ?? "--"
        return showLabel ? "\(menuBarLabel) \(value)" : value
    }

    /// Token volume has no severity thresholds; always `.normal`.
    static func menuBarTextStyle(for aggregate: TokenAggregate?) -> CPUMenuBarTextStyle {
        .normal
    }

    /// Whether there is nothing meaningful to show (no logs or an all-zero aggregate).
    static func isEmpty(_ aggregate: TokenAggregate?) -> Bool {
        guard let aggregate else { return true }
        return aggregate.total == 0
    }

    /// The defined empty/zero state copy, never an error or bare `0`.
    static func emptyState(_ language: AppLanguage = .current) -> String {
        Strings.tokenEmptyState(language)
    }

    /// Friendly display name for a raw Claude Code model id, e.g. `claude-opus-4-8` →
    /// `Opus 4.8`, `claude-3-5-sonnet-20241022` → `Sonnet 3.5`. Returns `nil` for empty or
    /// synthetic ids (nothing meaningful to show). Unknown vendors fall back to the id with
    /// any leading `claude-` stripped so the label never goes blank for a real model.
    static func modelDisplayName(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = id.lowercased()
        guard !lower.isEmpty, lower != "<synthetic>" else { return nil }

        let families = [("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")]
        guard let family = families.first(where: { lower.contains($0.0) }) else {
            if let openAI = openAIDisplayName(lower) { return openAI }
            return lower.hasPrefix("claude-") ? String(id.dropFirst("claude-".count)) : id
        }

        // Version components are the short numeric segments (e.g. 4-8, or 3-5 before the
        // family); long date suffixes like 20241022 are excluded by the length guard.
        let nums = lower.components(separatedBy: "-").filter { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        guard let major = nums.first else { return family.1 }
        let version = nums.count >= 2 ? "\(major).\(nums[1])" : major
        return "\(family.1) \(version)"
    }

    /// Friendly display name for an OpenAI model id, or `nil` if it is not one. Maps
    /// `gpt-*` ids to `GPT-<version> <Suffix…>` (e.g. `gpt-5-codex` → `GPT-5 Codex`,
    /// `gpt-5.5` → `GPT-5.5`) and `o<digit>*` ids to `o<version> <Suffix…>`
    /// (e.g. `o4-mini` → `o4 Mini`, `o3` → `o3`). Expects an already-lowercased id.
    private static func openAIDisplayName(_ lower: String) -> String? {
        if lower.hasPrefix("gpt-") {
            return friendlyName(prefix: "GPT-", body: String(lower.dropFirst("gpt-".count)))
        }
        // o-series: an "o" immediately followed by a digit (avoids "omni"-style ids).
        if lower.count >= 2, lower.hasPrefix("o"), lower[lower.index(after: lower.startIndex)].isNumber {
            return friendlyName(prefix: "", body: lower)
        }
        return nil
    }

    /// `<prefix><version> <Suffix…>` from a hyphen-separated body: the first segment is the
    /// version (kept as-is), remaining segments are capitalized (e.g. `codex` → `Codex`).
    private static func friendlyName(prefix: String, body: String) -> String {
        let parts = body.split(separator: "-").map(String.init)
        guard let version = parts.first else { return prefix.isEmpty ? body : prefix }
        let suffixes = parts.dropFirst().map { $0.capitalized }
        return (["\(prefix)\(version)"] + suffixes).joined(separator: " ")
    }

    /// Estimated USD cost for the popover: `$0.00` for zero, `< $0.01` below one cent,
    /// two decimals up to $10 (`$0.04`, `$1.23`), one decimal up to $100 (`$12.4`),
    /// whole dollars above. Defensively clamped — negative, NaN, or infinite input
    /// renders as `$0.00`, never a misleading or impossible value (ADR-003).
    static func costString(_ usd: Double) -> String {
        guard usd.isFinite, usd > 0 else { return "$0.00" }

        if usd < 0.01 { return "< $0.01" }
        if usd < 10 { return String(format: "$%.2f", usd) }
        if usd < 100 { return String(format: "$%.1f", usd) }
        return String(format: "$%.0f", usd)
    }

    /// One-line pace string for the popover burn-rate row (ADR-004):
    /// "123.4k/h · $0.85/h · ~$20.4/day". Reuses `humanized` and `costString`, so the
    /// output inherits their clamping — pathological values never render NaN or
    /// negative text. Tokens/hour rounds to the nearest integer before humanizing.
    static func burnRateString(
        _ breakdown: TokenBurnRateBreakdown,
        language: AppLanguage = .current
    ) -> String {
        let tokens = breakdown.tokensPerHour.isFinite
            ? Int(max(0, breakdown.tokensPerHour).rounded())
            : 0
        let day = Strings.tokenPerDayUnit(language)
        return "\(humanized(tokens))/h · \(costString(breakdown.costPerHourUSD))/h · ~\(costString(breakdown.costPerDayUSD))/\(day)"
    }

    /// One-line 5h-block string for the popover limit row (ADR-006):
    /// "1.2M · ~$4.10 · resets 17:30". Usage is the headline figure (cache
    /// excluded); the reset hour follows the user's 12/24h locale convention.
    /// Pure — block, language, locale, and time zone all injected; inherits
    /// `humanized`/`costString` clamping, so pathological values never render
    /// NaN or negative text.
    static func limitBlockString(
        _ block: TokenRateLimitBlock,
        language: AppLanguage = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let reset = formatter.string(from: block.end)
        return "\(humanized(block.usage.usageTotal)) · ~\(costString(block.costUSD)) · \(Strings.tokenLimitResetsAt(language)) \(reset)"
    }

    /// Rolling 7-day string for the weekly limit row (ADR-007): "8.4M · ~$31.2".
    static func limitWeeklyString(usage: TokenAggregate, costUSD: Double) -> String {
        "\(humanized(usage.usageTotal)) · ~\(costString(costUSD))"
    }

    /// Budget progress as a 0…1 fraction for the popover bar, or `nil` when the
    /// budget is off (≤ 0). Clamped — usage past the budget caps at 1 (ADR-008).
    static func budgetFraction(usage: Int, budget: Int) -> Double? {
        guard budget > 0 else { return nil }
        return min(1, Double(max(0, usage)) / Double(budget))
    }

    /// Budget percentage label, or `nil` when the budget is off. Clamps at 100%
    /// and appends the localized over-budget state instead of extrapolating —
    /// never "150%" (ADR-008).
    static func budgetPercentString(
        usage: Int,
        budget: Int,
        language: AppLanguage = .current
    ) -> String? {
        guard budget > 0 else { return nil }
        let clamped = max(0, usage)
        let percent = min(100, Int((Double(clamped) / Double(budget) * 100).rounded(.down)))
        return clamped > budget ? "100% · \(Strings.tokenBudgetOver(language))" : "\(percent)%"
    }

    /// Input / output / reasoning / cache breakdown rows for the popover. The reasoning row
    /// appears only when the aggregate reports it (Codex), so Claude keeps three rows
    /// (ADR-002). Cache combines read + creation into the single "cache" figure.
    static func breakdown(
        for aggregate: TokenAggregate,
        language: AppLanguage = .current
    ) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            (Strings.tokenInput(language), humanized(aggregate.input)),
            (Strings.tokenOutput(language), humanized(aggregate.output))
        ]
        if aggregate.reasoning > 0 {
            rows.append((Strings.tokenReasoning(language), humanized(aggregate.reasoning)))
        }
        rows.append((Strings.tokenCache(language), humanized(aggregate.cacheRead + aggregate.cacheCreation)))
        return rows
    }
}
