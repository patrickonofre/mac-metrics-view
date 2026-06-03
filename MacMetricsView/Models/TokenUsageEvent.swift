import Foundation

/// One parsed Claude Code token-usage record (`message.usage` from a session log line).
///
/// A pure value type: no I/O, timers, or formatting. `sessionID` is the source `.jsonl`
/// file id used for most-recently-used scope resolution; `projectDir` is the
/// `~/.claude/projects/<dir>` folder backing the project scope.
struct TokenUsageEvent: Equatable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    /// Hidden chain-of-thought tokens reasoning models bill separately from visible
    /// output (ADR-002/004). Claude has no such category and always passes 0; Codex
    /// supplies `reasoning_output_tokens`. Defaulted so existing Claude-shaped call
    /// sites stay source-compatible.
    let reasoningTokens: Int
    let sessionID: String
    let projectDir: String

    init(
        timestamp: Date,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        reasoningTokens: Int = 0,
        sessionID: String,
        projectDir: String
    ) {
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.sessionID = sessionID
        self.projectDir = projectDir
    }
}
