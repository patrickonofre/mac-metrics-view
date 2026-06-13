import Foundation

/// The app's UI language. Resolved from the system's preferred languages at runtime;
/// injectable so localized output can be unit-tested deterministically without
/// depending on the host's locale.
enum AppLanguage {
    case english
    case portuguese

    static var current: AppLanguage {
        resolve(preferred: Locale.preferredLanguages)
    }

    static func resolve(preferred: [String]) -> AppLanguage {
        for code in preferred {
            let lower = code.lowercased()
            if lower.hasPrefix("pt") { return .portuguese }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// A single piece of UI text in both supported languages.
struct LocalizedText {
    let en: String
    let pt: String

    func callAsFunction(_ language: AppLanguage = .current) -> String {
        switch language {
        case .english: return en
        case .portuguese: return pt
        }
    }
}

/// Central catalog of user-facing strings. CPU/RAM/NET/TEMP acronyms and numeric
/// units are intentionally not here — they read the same in both languages.
enum Strings {
    // Menu bar / general
    static let metricsPlaceholder = LocalizedText(en: "Metrics", pt: "Métricas")
    static let network = LocalizedText(en: "Network", pt: "Rede")
    static let temperature = LocalizedText(en: "Temperature", pt: "Temperatura")
    static let disk = LocalizedText(en: "Disk", pt: "Disco")
    /// VoiceOver description for the menu-bar warning glyph shown while the cleaning
    /// permission is missing.
    static let accessibilityWarningBadge = LocalizedText(
        en: "Cleaning permission needs attention",
        pt: "Permissão de limpeza precisa de atenção"
    )

    // Popover header / footer
    /// Reads `CFBundleShortVersionString` so the popover always reflects the shipped
    /// release instead of a hardcoded literal that goes stale every version.
    static func appVersion(_ language: AppLanguage = .current) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let prefix = language == .portuguese ? "versão" : "version"
        return "\(prefix): \(version)"
    }
    static let developedBy = LocalizedText(en: "Developed by Patrick Onofre", pt: "Desenvolvido por Patrick Onofre")
    static let updated = LocalizedText(en: "Updated", pt: "Atualizado")
    static let quit = LocalizedText(en: "Quit Mac Metrics View", pt: "Sair do Mac Metrics View")

    // CPU detail rows
    static let cpuUser = LocalizedText(en: "User", pt: "Usuário")
    static let cpuSystem = LocalizedText(en: "System", pt: "Sistema")
    static let cpuIdle = LocalizedText(en: "Idle", pt: "Ocioso")

    // RAM detail rows
    static let ramTotal = LocalizedText(en: "Total", pt: "Total")
    static let ramUsed = LocalizedText(en: "Used", pt: "Usado")
    static let ramAppMemory = LocalizedText(en: "App Memory", pt: "Memória de apps")
    static let ramPressure = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramMenuBarMetric = LocalizedText(en: "RAM value", pt: "Valor RAM")
    static let ramMetricAppMemoryShort = LocalizedText(en: "App", pt: "Apps")
    static let ramMetricPressureShort = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramMenuBarMetricHelpTitle = LocalizedText(
        en: "Which RAM value is shown",
        pt: "Qual valor de RAM é exibido"
    )
    static let ramAppMemoryHelp = LocalizedText(
        en: "Memory actively used by apps (GB). Rises and falls as you open and close apps.",
        pt: "Memória usada ativamente pelos apps (GB). Sobe e desce ao abrir e fechar apps."
    )
    static let ramPressureHelp = LocalizedText(
        en: "How stressed memory is overall (%). Stays low under normal use; climbs only when the system runs short on memory.",
        pt: "O quanto a memória está sob estresse no geral (%). Fica baixa no uso normal; só sobe quando falta memória."
    )

    // Network detail rows (loanwords, identical in both)
    static let download = LocalizedText(en: "Download", pt: "Download")
    static let upload = LocalizedText(en: "Upload", pt: "Upload")

    // Disk detail rows + picker. Recent totals/peaks are a rolling sparkline
    // window (~45s) per ADR-002 — labels say so to avoid a "since launch" read.
    static let diskRead = LocalizedText(en: "Read", pt: "Leitura")
    static let diskWrite = LocalizedText(en: "Write", pt: "Escrita")
    static let diskRecentTotalRead = LocalizedText(en: "Recent read (~45s)", pt: "Leitura recente (~45s)")
    static let diskRecentTotalWrite = LocalizedText(en: "Recent write (~45s)", pt: "Escrita recente (~45s)")
    static let diskRecentPeakRead = LocalizedText(en: "Peak read (~45s)", pt: "Pico de leitura (~45s)")
    static let diskRecentPeakWrite = LocalizedText(en: "Peak write (~45s)", pt: "Pico de escrita (~45s)")
    static let diskMenuBarMetric = LocalizedText(en: "Disk value", pt: "Valor Disco")
    static let diskMetricCombinedShort = LocalizedText(en: "Total", pt: "Total")
    static let diskMetricSplitShort = LocalizedText(en: "R/W", pt: "L/E")

    // Token usage meter (Claude Code). "Tokens" is a loanword, identical in both.
    static let tokens = LocalizedText(en: "Tokens", pt: "Tokens")
    static let tokenInput = LocalizedText(en: "Input", pt: "Entrada")
    static let tokenOutput = LocalizedText(en: "Output", pt: "Saída")
    static let tokenReasoning = LocalizedText(en: "Reasoning", pt: "Raciocínio")
    static let tokenCache = LocalizedText(en: "Cache", pt: "Cache")
    static let tokenReset = LocalizedText(en: "Reset counter", pt: "Zerar contador")
    static let tokenEmptyState = LocalizedText(en: "No token usage yet", pt: "Sem uso de tokens ainda")
    // Scope picker (which Claude Code activity is counted)
    static let tokenScopeLabel = LocalizedText(en: "Scope", pt: "Escopo")
    static let tokenScopeGlobal = LocalizedText(en: "Global", pt: "Global")
    static let tokenScopeProject = LocalizedText(en: "Project", pt: "Projeto")
    static let tokenScopeSession = LocalizedText(en: "Session", pt: "Sessão")
    // Provider picker (which tool's local logs are counted). "Claude"/"Codex" are product
    // names, identical in both languages; only "Combined" translates.
    static let tokenProviderLabel = LocalizedText(en: "Provider", pt: "Provedor")
    static let tokenProviderClaude = LocalizedText(en: "Claude", pt: "Claude")
    static let tokenProviderCodex = LocalizedText(en: "Codex", pt: "Codex")
    static let tokenProviderGemini = LocalizedText(en: "Gemini", pt: "Gemini")
    static let tokenProviderCombined = LocalizedText(en: "Combined", pt: "Combinado")
    // Window picker (rolling range shown)
    static let tokenWindowLabel = LocalizedText(en: "Token window", pt: "Janela de tokens")
    static let tokenWindowToday = LocalizedText(en: "Today", pt: "Hoje")
    static let tokenWindowLastHour = LocalizedText(en: "Last hour", pt: "Última hora")
    static let tokenWindowLast24h = LocalizedText(en: "Last 24h", pt: "Últimas 24h")
    static let tokenWindowSinceReset = LocalizedText(en: "Since reset", pt: "Desde o reset")
    // Estimated cost (Phase 1). The label itself carries the "estimated" qualifier and
    // the note reinforces it — the app must never imply billing authority (PRD).
    static let tokenCostLabel = LocalizedText(en: "Est. cost", pt: "Custo est.")
    static let tokenCostEstimatedNote = LocalizedText(
        en: "Estimated at API list prices — not a bill.",
        pt: "Estimativa pelos preços de tabela da API — não é uma fatura."
    )
    /// Shown when events from unrecognized models were excluded from the total
    /// (ADR-003): the figure under-reports rather than guessing a price.
    static let tokenCostUnpricedNote = LocalizedText(
        en: "≈ usage from unrecognized models not included",
        pt: "≈ uso de modelos não reconhecidos não incluído"
    )
    // Burn rate / pace line (Phase 2, ADR-004). One-word label — the pace line is
    // already dense. No "estimated" disclaimer here: the line lives in the block
    // that carries the Phase 1 note.
    static let tokenPaceLabel = LocalizedText(en: "Pace", pt: "Ritmo")
    /// Per-day unit word for the "~$X/day" projection; "/h" reads the same in both.
    static let tokenPerDayUnit = LocalizedText(en: "day", pt: "dia")

    // Rate-limit window estimate (Phase 3, ADR-006/007/008). Short labels — the
    // limit rows are caption-sized; the disclaimer carries the mandatory
    // "estimate, this Mac only" qualifier (PRD UX rule).
    static let tokenLimitBlockLabel = LocalizedText(en: "5h block", pt: "Bloco 5h")
    static let tokenLimitWeekLabel = LocalizedText(en: "7 days", pt: "7 dias")
    /// Verb preceding the block's reset time, e.g. "resets 17:30".
    static let tokenLimitResetsAt = LocalizedText(en: "resets", pt: "reinicia")
    static let tokenLimitNoActiveBlock = LocalizedText(en: "No active block", pt: "Nenhum bloco ativo")
    static let tokenLimitDisclaimer = LocalizedText(
        en: "Estimate — this Mac only.",
        pt: "Estimativa — só este Mac."
    )
    // Optional user-set budgets (ADR-008): plain token counts, 0 = off.
    static let tokenBudgetSessionLabel = LocalizedText(en: "5h budget", pt: "Orçamento 5h")
    static let tokenBudgetWeeklyLabel = LocalizedText(en: "Weekly budget", pt: "Orçamento semanal")
    /// Suffix marking usage past the configured budget — clamped, never "150%".
    static let tokenBudgetOver = LocalizedText(en: "over budget", pt: "acima do orçamento")
    /// Placeholder suggesting how to derive a value (tokens, 0 = off).
    static let tokenBudgetPlaceholder = LocalizedText(en: "0 = off", pt: "0 = desligado")

    // Source/coverage note: explains which usage the counter can see.
    static let tokenSourceHelpTitle = LocalizedText(
        en: "Which usage is counted",
        pt: "Qual uso é contabilizado"
    )
    static let tokenSourceHelp = LocalizedText(
        en: "Counts come from Claude Code session logs (~/.claude). Every Claude model used in Claude Code is included (Opus, Sonnet, Haiku). API usage and other apps aren't tracked.",
        pt: "A contagem vem dos logs de sessão do Claude Code (~/.claude). Inclui todos os modelos Claude usados no Claude Code (Opus, Sonnet, Haiku). Uso via API ou outros apps não é contabilizado."
    )

    static func tokenScopeName(_ scope: TokenScope) -> LocalizedText {
        switch scope {
        case .global: return tokenScopeGlobal
        case .project: return tokenScopeProject
        case .session: return tokenScopeSession
        }
    }

    static func tokenWindowName(_ window: TokenWindow) -> LocalizedText {
        switch window {
        case .today: return tokenWindowToday
        case .lastHour: return tokenWindowLastHour
        case .last24h: return tokenWindowLast24h
        case .sinceReset: return tokenWindowSinceReset
        }
    }

    static func tokenProviderName(_ selection: TokenProviderSelection) -> LocalizedText {
        switch selection {
        case .claude: return tokenProviderClaude
        case .codex: return tokenProviderCodex
        case .gemini: return tokenProviderGemini
        case .combined: return tokenProviderCombined
        }
    }

    // Visibility / display controls
    static let displayLabel = LocalizedText(en: "Display", pt: "Exibição")
    static let displayIcon = LocalizedText(en: "Icon", pt: "Ícone")
    static let displayText = LocalizedText(en: "Label", pt: "Rótulo")

    // Empty state
    static let noMetricsTitle = LocalizedText(en: "No Metrics Visible", pt: "Nenhuma métrica visível")
    static let noMetricsHint = LocalizedText(
        en: "Turn on CPU, RAM, Network, Disk, or Temperature to show live values.",
        pt: "Ative CPU, RAM, Rede, Disco ou Temperatura para ver valores ao vivo."
    )

    // Severity labels (CPU/RAM/temperature share these in the popover)
    static let severityElevated = LocalizedText(en: "Elevated", pt: "Elevado")
    static let severityHigh = LocalizedText(en: "High", pt: "Alto")

    // Temperature
    static let temperatureStateRow = LocalizedText(en: "State", pt: "Estado")
    static let tempNormal = LocalizedText(en: "Normal", pt: "Normal")
    static let tempWarm = LocalizedText(en: "Warm", pt: "Aquecido")
    static let tempHot = LocalizedText(en: "Hot", pt: "Quente")
    static let tempCritical = LocalizedText(en: "Critical", pt: "Crítico")

    // Launch at login
    static let openAtLogin = LocalizedText(en: "Open at login", pt: "Abrir ao inicializar")
    static let loginChangeFailed = LocalizedText(en: "Couldn't change it right now.", pt: "Não foi possível alterar agora.")
    static let loginEnabled = LocalizedText(en: "Enabled", pt: "Ativado")
    static let loginDisabled = LocalizedText(en: "Disabled", pt: "Desativado")
    static let loginError = LocalizedText(en: "Error", pt: "Erro")

    // Auto-update
    static let autoUpdateCheck = LocalizedText(en: "Check for updates…", pt: "Buscar atualizações…")
    static func autoUpdateAvailable(_ version: String, _ language: AppLanguage = .current) -> String {
        switch language {
        case .english: return "New version \(version) available"
        case .portuguese: return "Nova versão \(version) disponível"
        }
    }
    static let updateNow = LocalizedText(en: "Update now", pt: "Atualizar agora")
    static let whatsNew = LocalizedText(en: "What's new", pt: "Novidades")

    // Cleaning-lock Accessibility recovery (self-healing flow). Tone matches the
    // existing Portuguese cleaning-section copy; the dead-end "reload" wording is
    // gone — the app now applies a restored grant on its own.
    static let cleaningPermissionRequired = LocalizedText(
        en: "Accessibility permission required",
        pt: "Permissão de Acessibilidade necessária"
    )
    static let cleaningOpenAccessibility = LocalizedText(
        en: "Open Accessibility",
        pt: "Abrir Acessibilidade"
    )
    /// Update-reset case: stresses remove (−) + re-add, since re-toggling the stale
    /// entry never works.
    static let cleaningRecoveryResetGuidance = LocalizedText(
        en: "The update reset this permission. In Accessibility, remove (−) Mac Metrics View and add it again — just re-enabling the old entry won't work. The app applies it and reopens on its own.",
        pt: "A atualização redefiniu esta permissão. Em Acessibilidade, remova (−) o Mac Metrics View e adicione novamente — apenas reativar a entrada antiga não funciona. O app aplica e reabre sozinho."
    )
    /// First-time grant case.
    static let cleaningRecoveryFirstGrantGuidance = LocalizedText(
        en: "Grant access under Accessibility. If Mac Metrics View is already listed but still blocked, remove (−) the entry and add it again — an entry from an earlier version won't work. The app applies it and reopens on its own.",
        pt: "Conceda o acesso em Acessibilidade. Se o Mac Metrics View já aparece na lista mas continua bloqueado, remova (−) a entrada e adicione novamente — uma entrada de uma versão anterior não vale. O app aplica e reabre sozinho."
    )
    /// Shown while the probe loop is running and the user is acting in Settings.
    static let cleaningRecoveryChecking = LocalizedText(
        en: "Checking automatically — no need to come back here.",
        pt: "Verificando automaticamente — não precisa voltar aqui."
    )
    /// Transient state while the detected grant is applied via relaunch.
    static let cleaningApplyingPermission = LocalizedText(
        en: "Applying permission… reopening",
        pt: "Aplicando permissão… reabrindo"
    )
    // Popover header recovery banner.
    static let recoveryBannerResetTitle = LocalizedText(
        en: "Cleaning is paused",
        pt: "A limpeza está pausada"
    )
    static let recoveryBannerResetMessage = LocalizedText(
        en: "An update reset the Accessibility permission. Re-apply it below.",
        pt: "Uma atualização redefiniu a permissão de Acessibilidade. Reaplique abaixo."
    )
    static let recoveryBannerNeedsGrantTitle = LocalizedText(
        en: "Cleaning needs Accessibility",
        pt: "A limpeza precisa de Acessibilidade"
    )
    static let recoveryBannerNeedsGrantMessage = LocalizedText(
        en: "Grant Accessibility permission to use the cleaning feature.",
        pt: "Conceda a permissão de Acessibilidade para usar o modo limpeza."
    )

    // Shared
    static let unavailable = LocalizedText(en: "Unavailable", pt: "Indisponível")
}
