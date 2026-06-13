import Foundation

/// USD per million tokens for one model family + version. Pure value type (ADR-002):
/// absolute per-category rates, so vendor differences (Anthropic cache-write premium vs
/// OpenAI cached-input discount) live in the table, never in the cost math.
struct TokenModelRates: Equatable {
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
}

/// Static, release-shipped price table mapping raw model ids to USD/MTok rates
/// (ADR-002). Family/version resolution mirrors `TokenFormatter.modelDisplayName`:
/// short numeric segments are version components, long date suffixes are excluded.
/// Unknown ids resolve to `nil` — the caller must never substitute a guessed price
/// (ADR-003).
///
/// Rates verified against the official pricing references at implementation time
/// (2026-06-11); re-verifying them is a release-runbook item.
enum TokenPricing {

    /// Resolves a raw model id (e.g. `claude-opus-4-8`, `gpt-5-codex`) to rates, or
    /// `nil` when the id matches no entry.
    static func rates(for modelID: String) -> TokenModelRates? {
        let lower = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, lower != "<synthetic>" else { return nil }

        if let anthropic = anthropicRates(lower) { return anthropic }
        if let openAI = openAIRates(lower) { return openAI }
        return geminiRates(lower)
    }

    // MARK: - Anthropic

    /// Anthropic billing: cache read = 0.1× input, cache write = 1.25× input. Session
    /// logs do not expose the 5m-vs-1h cache-write TTL split, so the table uses the
    /// 1.25× (5-minute) rate — accepted under the "estimated" framing (ADR-002).
    private static func anthropic(_ input: Double, _ output: Double) -> TokenModelRates {
        TokenModelRates(
            inputPerMTok: input,
            outputPerMTok: output,
            cacheReadPerMTok: input * 0.1,
            cacheWritePerMTok: input * 1.25
        )
    }

    private static func anthropicRates(_ lower: String) -> TokenModelRates? {
        if lower.contains("fable") { return anthropic(10, 50) }
        if lower.contains("opus") {
            // Opus pricing dropped to 5/25 starting at 4.5; 4.0/4.1 and 3.x billed
            // 15/75. Unversioned ids assume the current generation.
            guard let version = version(of: lower) else { return anthropic(5, 25) }
            return version >= 4.5 ? anthropic(5, 25) : anthropic(15, 75)
        }
        if lower.contains("sonnet") { return anthropic(3, 15) }
        if lower.contains("haiku") {
            guard let version = version(of: lower) else { return anthropic(1, 5) }
            if version >= 4 { return anthropic(1, 5) }
            return version >= 3.5 ? anthropic(0.8, 4) : anthropic(0.25, 1.25)
        }
        return nil
    }

    /// major.minor from the id's short numeric segments, mirroring the parsing in
    /// `TokenFormatter.modelDisplayName` (date suffixes excluded by the length guard).
    private static func version(of lower: String) -> Double? {
        let nums = lower.components(separatedBy: "-").filter { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        guard let major = nums.first, let majorValue = Double(major) else { return nil }
        guard nums.count >= 2, let minorValue = Double(nums[1]) else { return majorValue }
        return majorValue + minorValue / 10
    }

    // MARK: - OpenAI (Codex)

    /// OpenAI billing: cached input is a discounted absolute rate; cache writes carry
    /// no premium (billed as regular input). Codex session logs report no
    /// cache-creation tokens, so the write rate is effectively unused for this vendor.
    private static func openAI(_ input: Double, _ output: Double, cachedInput: Double) -> TokenModelRates {
        TokenModelRates(
            inputPerMTok: input,
            outputPerMTok: output,
            cacheReadPerMTok: cachedInput,
            cacheWritePerMTok: input
        )
    }

    private static func openAIRates(_ lower: String) -> TokenModelRates? {
        if lower.hasPrefix("gpt-5") {
            // OpenAI re-priced the gpt-5.x line per minor version (official pricing
            // page, verified 2026-06-12): 5.5 = 5/30, 5.4 = 2.50/15, 5.3 (incl.
            // codex) = 1.75/14; 5.0/5.1 keep the original 1.25/10. 5.2 has no
            // published price — resolve to nil so it degrades to the unpriced
            // indicator instead of a guess (ADR-003).
            let minor = gpt5Minor(lower)
            if lower.contains("nano") {
                return minor >= 4
                    ? openAI(0.20, 1.25, cachedInput: 0.02)
                    : openAI(0.05, 0.40, cachedInput: 0.005)
            }
            if lower.contains("mini") {
                return minor >= 4
                    ? openAI(0.75, 4.5, cachedInput: 0.075)
                    : openAI(0.25, 2, cachedInput: 0.025)
            }
            switch minor {
            case 5...: return openAI(5, 30, cachedInput: 0.50)
            case 4: return openAI(2.50, 15, cachedInput: 0.25)
            case 3: return openAI(1.75, 14, cachedInput: 0.175)
            case 2: return nil
            default: return openAI(1.25, 10, cachedInput: 0.125)   // gpt-5, gpt-5.1
            }
        }
        if lower.hasPrefix("o3-mini") { return openAI(1.1, 4.4, cachedInput: 0.55) }
        if lower.hasPrefix("o4-mini") { return openAI(1.1, 4.4, cachedInput: 0.275) }
        if lower.hasPrefix("o3") { return openAI(2, 8, cachedInput: 0.5) }
        return nil
    }

    // MARK: - Google (Gemini CLI)

    /// Gemini billing: cached input is a discounted absolute rate; Gemini reports no
    /// cache-creation tokens, so the write rate is effectively unused and billed as
    /// regular input. `thoughts` tokens map to `reasoningTokens` and bill at the output
    /// rate in `TokenCostCalculator` (ADR-002/011).
    private static func gemini(_ input: Double, _ output: Double, cachedInput: Double) -> TokenModelRates {
        TokenModelRates(
            inputPerMTok: input,
            outputPerMTok: output,
            cacheReadPerMTok: cachedInput,
            cacheWritePerMTok: input
        )
    }

    /// Flat ≤200k-context tier (ADR-011): Gemini's published prices roughly double above
    /// a 200k-token prompt, but the table ships one flat rate per model under the
    /// "estimated" framing — the >200k premium is the accepted estimate error. Unknown
    /// `gemini-*` ids resolve to `nil` so they surface as unpriced, never a guess
    /// (ADR-003). Rates verified against the official Gemini pricing page at
    /// implementation time (2026-06-13); re-verifying them is a release-runbook item.
    private static func geminiRates(_ lower: String) -> TokenModelRates? {
        guard lower.hasPrefix("gemini") else { return nil }
        // flash-lite must precede flash (it also contains "flash").
        if lower.contains("flash-lite") { return gemini(0.10, 0.40, cachedInput: 0.025) }
        if lower.contains("flash") {
            // 2.5 Flash is priced above 2.0 Flash; unversioned/2.0 keep the lower tier.
            if let version = geminiVersion(lower), version >= 2.5 {
                return gemini(0.30, 2.50, cachedInput: 0.075)
            }
            return gemini(0.10, 0.40, cachedInput: 0.025)
        }
        if lower.contains("pro") { return gemini(1.25, 10, cachedInput: 0.31) }
        return nil
    }

    /// Dotted major.minor from a `gemini-<x.y>-…` id (`gemini-2.5-flash` → 2.5). Gemini
    /// ids use a dotted version segment, unlike the dash-separated Claude/OpenAI ids that
    /// `version(of:)` parses.
    private static func geminiVersion(_ lower: String) -> Double? {
        guard let range = lower.range(of: "gemini-") else { return nil }
        let digits = lower[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    /// Minor version of a `gpt-5.x` id (`gpt-5.3-codex` → 3); `gpt-5`/`gpt-5-codex`
    /// (no dot) → 0.
    private static func gpt5Minor(_ lower: String) -> Int {
        guard lower.hasPrefix("gpt-5.") else { return 0 }
        let digits = lower.dropFirst("gpt-5.".count).prefix(while: \.isNumber)
        return Int(digits) ?? 0
    }
}
