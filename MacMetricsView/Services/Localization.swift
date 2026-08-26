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

    // Popover tab titles (redesign). Metrics reuses `metricsPlaceholder`.
    static let settingsTab = LocalizedText(en: "Settings", pt: "Ajustes")
    static let actionsTab = LocalizedText(en: "Actions", pt: "Ações")
    // Card expand/collapse accessibility actions (redesign).
    static let cardExpand = LocalizedText(en: "Expand", pt: "Expandir")
    static let cardCollapse = LocalizedText(en: "Collapse", pt: "Recolher")
    static let temperature = LocalizedText(en: "Temperature", pt: "Temperatura")
    static let disk = LocalizedText(en: "Disk", pt: "Disco")
    static let gpu = LocalizedText(en: "GPU", pt: "GPU")

    // Battery
    static let battery = LocalizedText(en: "Battery", pt: "Bateria")
    static let batteryPowerSource = LocalizedText(en: "Power source", pt: "Fonte")
    static let batteryOnAC = LocalizedText(en: "AC", pt: "Tomada")
    static let batteryOnBattery = LocalizedText(en: "Battery", pt: "Bateria")
    static let batteryTimeRemaining = LocalizedText(en: "Time left", pt: "Tempo restante")
    static let batteryCalculating = LocalizedText(en: "Calculating…", pt: "Calculando…")
    static let batteryHealth = LocalizedText(en: "Health", pt: "Saúde")
    static let batteryHealthNormal = LocalizedText(en: "Normal", pt: "Normal")
    static let batteryServiceRecommended = LocalizedText(en: "Service Recommended", pt: "Serviço recomendado")
    static let batteryCycles = LocalizedText(en: "Cycles", pt: "Ciclos")
    static let batteryNoBattery = LocalizedText(en: "No battery", pt: "Sem bateria")

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
    
    // Settings Update Rate
    static let updateRateLabel = LocalizedText(en: "Update Rate", pt: "Taxa de Atualização")
    static let updateRateSeconds1 = LocalizedText(en: "1 second", pt: "1 segundo")
    static let updateRateSeconds2 = LocalizedText(en: "2 seconds", pt: "2 segundos")
    static let updateRateSeconds3 = LocalizedText(en: "3 seconds", pt: "3 segundos")

    // CPU detail rows
    static let cpuUser = LocalizedText(en: "User", pt: "Usuário")
    static let cpuSystem = LocalizedText(en: "System", pt: "Sistema")
    static let cpuIdle = LocalizedText(en: "Idle", pt: "Ocioso")
    static let cpuSampling = LocalizedText(en: "sampling…", pt: "amostrando…")

    // RAM detail rows
    static let ramTotal = LocalizedText(en: "Total", pt: "Total")
    static let ramUsed = LocalizedText(en: "Used", pt: "Usado")
    static let ramAppMemory = LocalizedText(en: "App Memory", pt: "Memória de apps")
    static let ramPressure = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramWired = LocalizedText(en: "Wired", pt: "Reservada")
    static let ramCompressed = LocalizedText(en: "Compressed", pt: "Comprimida")
    static let ramCachedFiles = LocalizedText(en: "Cached Files", pt: "Arquivos em cache")
    static let ramSwapUsed = LocalizedText(en: "Swap Used", pt: "Swap usado")
    static let ramPressureLevel = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramPressureNormal = LocalizedText(en: "Normal", pt: "Normal")
    static let ramPressureWarning = LocalizedText(en: "Warning", pt: "Atenção")
    static let ramPressureCritical = LocalizedText(en: "Critical", pt: "Crítica")
    static let ramMenuBarMetric = LocalizedText(en: "RAM value", pt: "Valor RAM")
    static let ramMetricUsedTotalShort = LocalizedText(en: "Used / Total", pt: "Usado / Total")
    static let ramMetricAppMemoryShort = LocalizedText(en: "App", pt: "Apps")
    static let ramMetricPressureShort = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramMenuBarMetricHelpTitle = LocalizedText(
        en: "Which RAM value is shown",
        pt: "Qual valor de RAM é exibido"
    )
    static let ramUsedTotal = LocalizedText(en: "Used / Total", pt: "Usado / Total")
    static let ramUsedTotalHelp = LocalizedText(
        en: "Memory used vs. your Mac's total (GB). The color still reflects memory pressure, not how full memory is.",
        pt: "Memória usada vs. o total do seu Mac (GB). A cor ainda reflete a pressão de memória, não o quanto está cheia."
    )
    static let ramAppMemoryHelp = LocalizedText(
        en: "Memory actively used by apps (GB). Rises and falls as you open and close apps.",
        pt: "Memória usada ativamente pelos apps (GB). Sobe e desce ao abrir e fechar apps."
    )
    static let ramPressureHelp = LocalizedText(
        en: "How stressed memory is overall (%). Stays low under normal use; climbs only when the system runs short on memory.",
        pt: "O quanto a memória está sob estresse no geral (%). Fica baixa no uso normal; só sobe quando falta memória."
    )

    // Network detail rows (loanwords, identical in both). Recent totals/peaks are a
    // rolling sparkline window (~45s) per ADR-002 — labels say so to avoid a
    // "since launch" read, mirroring the disk detail rows.
    static let download = LocalizedText(en: "Download", pt: "Download")
    static let upload = LocalizedText(en: "Upload", pt: "Upload")
    static let netRecentTotalDownload = LocalizedText(en: "Recent download (~45s)", pt: "Download recente (~45s)")
    static let netRecentTotalUpload = LocalizedText(en: "Recent upload (~45s)", pt: "Upload recente (~45s)")
    static let netRecentPeakDownload = LocalizedText(en: "Peak download (~45s)", pt: "Pico de download (~45s)")
    static let netRecentPeakUpload = LocalizedText(en: "Peak upload (~45s)", pt: "Pico de upload (~45s)")
    // Since-launch cumulative totals (reset each launch), distinct from the ~45s window.
    static let netSessionDownload = LocalizedText(en: "Session download", pt: "Download da sessão")
    static let netSessionUpload = LocalizedText(en: "Session upload", pt: "Upload da sessão")

    // Disk detail rows + picker. Recent totals/peaks are a rolling sparkline
    // window (~45s) per ADR-002 — labels say so to avoid a "since launch" read.
    static let diskRead = LocalizedText(en: "Read", pt: "Leitura")
    static let diskWrite = LocalizedText(en: "Write", pt: "Escrita")
    static let diskRecentTotalRead = LocalizedText(en: "Recent read (~45s)", pt: "Leitura recente (~45s)")
    static let diskRecentTotalWrite = LocalizedText(en: "Recent write (~45s)", pt: "Escrita recente (~45s)")
    static let diskRecentPeakRead = LocalizedText(en: "Peak read (~45s)", pt: "Pico de leitura (~45s)")
    static let diskRecentPeakWrite = LocalizedText(en: "Peak write (~45s)", pt: "Pico de escrita (~45s)")
    // Since-launch cumulative totals (reset each launch), distinct from the ~45s window.
    static let diskSessionRead = LocalizedText(en: "Session read", pt: "Leitura da sessão")
    static let diskSessionWrite = LocalizedText(en: "Session write", pt: "Escrita da sessão")
    static let diskMenuBarMetric = LocalizedText(en: "Disk value", pt: "Valor Disco")
    static let diskMetricCombinedShort = LocalizedText(en: "Total", pt: "Total")
    static let diskMetricSplitShort = LocalizedText(en: "R/W", pt: "L/E")

    // Retained until the token collection stack is deleted in T2.
    static let tokens = LocalizedText(en: "Tokens", pt: "Tokens")
    static let tokenInput = LocalizedText(en: "Input", pt: "Entrada")
    static let tokenOutput = LocalizedText(en: "Output", pt: "Saída")
    static let tokenReasoning = LocalizedText(en: "Reasoning", pt: "Raciocínio")
    static let tokenCache = LocalizedText(en: "Cache", pt: "Cache")
    static let tokenReset = LocalizedText(en: "Reset counter", pt: "Zerar contador")
    static let tokenEmptyState = LocalizedText(en: "No token usage yet", pt: "Sem uso de tokens ainda")
    static let tokenScopeLabel = LocalizedText(en: "Scope", pt: "Escopo")
    static let tokenScopeGlobal = LocalizedText(en: "Global", pt: "Global")
    static let tokenScopeProject = LocalizedText(en: "Project", pt: "Projeto")
    static let tokenScopeSession = LocalizedText(en: "Session", pt: "Sessão")
    static let tokenProviderLabel = LocalizedText(en: "Provider", pt: "Provedor")
    static let tokenProviderClaude = LocalizedText(en: "Claude", pt: "Claude")
    static let tokenProviderCodex = LocalizedText(en: "Codex", pt: "Codex")
    static let tokenProviderCombined = LocalizedText(en: "Combined", pt: "Combinado")
    static let tokenWindowLabel = LocalizedText(en: "Token window", pt: "Janela de tokens")
    static let tokenWindowToday = LocalizedText(en: "Today", pt: "Hoje")
    static let tokenWindowLastHour = LocalizedText(en: "Last hour", pt: "Última hora")
    static let tokenWindowLast24h = LocalizedText(en: "Last 24h", pt: "Últimas 24h")
    static let tokenWindowSinceReset = LocalizedText(en: "Since reset", pt: "Desde o reset")
    static let tokenCostLabel = LocalizedText(en: "Est. cost", pt: "Custo est.")
    static let tokenCostEstimatedNote = LocalizedText(en: "Estimated at API list prices — not a bill.", pt: "Estimativa pelos preços de tabela da API — não é uma fatura.")
    static let tokenCostUnpricedNote = LocalizedText(en: "≈ usage from unrecognized models not included", pt: "≈ uso de modelos não reconhecidos não incluído")
    static let tokenPaceLabel = LocalizedText(en: "Pace", pt: "Ritmo")
    static let tokenPerDayUnit = LocalizedText(en: "day", pt: "dia")
    static let tokenLimitBlockLabel = LocalizedText(en: "5h block", pt: "Bloco 5h")
    static let tokenLimitWeekLabel = LocalizedText(en: "7 days", pt: "7 dias")
    static let tokenLimitResetsAt = LocalizedText(en: "resets", pt: "reinicia")
    static let tokenLimitNoActiveBlock = LocalizedText(en: "No active block", pt: "Nenhum bloco ativo")
    static let tokenLimitDisclaimer = LocalizedText(en: "Estimate — this Mac only.", pt: "Estimativa — só este Mac.")
    static let tokenBudgetSessionLabel = LocalizedText(en: "5h budget", pt: "Orçamento 5h")
    static let tokenBudgetWeeklyLabel = LocalizedText(en: "Weekly budget", pt: "Orçamento semanal")
    static let tokenBudgetOver = LocalizedText(en: "over budget", pt: "acima do orçamento")
    static let tokenBudgetPlaceholder = LocalizedText(en: "0 = off", pt: "0 = desligado")
    static let tokenSourceHelpTitle = LocalizedText(en: "Which usage is counted", pt: "Qual uso é contabilizado")
    static let tokenSourceHelp = LocalizedText(en: "Counts come from Claude Code session logs (~/.claude). Every Claude model used in Claude Code is included (Opus, Sonnet, Haiku). API usage and other apps aren't tracked.", pt: "A contagem vem dos logs de sessão do Claude Code (~/.claude). Inclui todos os modelos Claude usados no Claude Code (Opus, Sonnet, Haiku). Uso via API ou outros apps não é contabilizado.")

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

    // Keep awake
    static let keepAwakeTitle = LocalizedText(en: "Keep awake", pt: "Manter acordado")
    static let keepAwakeHint = LocalizedText(
        en: "Prevent the display and system from sleeping while on.",
        pt: "Impede a suspensão da tela e do sistema enquanto ativo."
    )

    // Lid-close keep-awake sub-mode (feature `lid-close-keep-awake`). Visible only
    // while base keep-awake is on (LIDC-01); the approval strings back the
    // pending-approval guidance card (LIDC-08).
    static let lidCloseTitle = LocalizedText(
        en: "Keep awake with lid closed",
        pt: "Manter acordado com a tampa fechada"
    )
    static let lidCloseHint = LocalizedText(
        en: "Keeps the Mac running with the lid closed. Turns itself off below 10% battery.",
        pt: "Mantém o Mac funcionando com a tampa fechada. Desliga sozinho abaixo de 10% de bateria."
    )
    static let lidClosePendingApprovalTitle = LocalizedText(
        en: "Waiting for approval",
        pt: "Aguardando aprovação"
    )
    static let lidClosePendingApprovalMessage = LocalizedText(
        en: "Allow Mac Metrics View in System Settings → General → Login Items, then turn the option on again. This approval is asked only once.",
        pt: "Permita o Mac Metrics View em Ajustes do Sistema → Geral → Itens de Início, depois ative a opção novamente. Esta aprovação é pedida só uma vez."
    )
    static let lidCloseOpenLoginItems = LocalizedText(
        en: "Open Login Items",
        pt: "Abrir Itens de Início"
    )

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

    /// Feature-level opt-in toggle (feature `cleaning-lock-opt-in`, CLNGT-03/04/05).
    static let cleaningLockEnable = LocalizedText(en: "Enable", pt: "Ativar")

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

    // Ambient-light theme suggestion (feature). Suggestion banner + settings.
    static let ambientSuggestionTitleDark = LocalizedText(
        en: "Switch to Dark theme?",
        pt: "Mudar para o tema Escuro?"
    )
    static let ambientSuggestionTitleLight = LocalizedText(
        en: "Switch to Light theme?",
        pt: "Mudar para o tema Claro?"
    )
    static let ambientSuggestionMessage = LocalizedText(
        en: "The light around your Mac changed.",
        pt: "A luz ao redor do seu Mac mudou."
    )
    static let ambientApply = LocalizedText(en: "Switch", pt: "Mudar")
    static let ambientDismiss = LocalizedText(en: "Not now", pt: "Agora não")
    static let ambientNotAuthorizedTitle = LocalizedText(
        en: "Automation permission needed",
        pt: "Permissão de automação necessária"
    )
    static let ambientNotAuthorizedMessage = LocalizedText(
        en: "Allow Mac Metrics View to control System Events in Privacy & Security → Automation.",
        pt: "Permita o Mac Metrics View controlar o System Events em Privacidade e Segurança → Automação."
    )
    static let ambientOpenAutomationSettings = LocalizedText(en: "Open Settings", pt: "Abrir Ajustes")

    static let ambientThemeSectionTitle = LocalizedText(
        en: "Auto theme by ambient light",
        pt: "Tema automático por luz ambiente"
    )
    static let ambientThemeEnable = LocalizedText(
        en: "Suggest theme by ambient light",
        pt: "Sugerir tema pela luz ambiente"
    )
    static let ambientThemeHelp = LocalizedText(
        en: "When the light around your Mac changes, suggest switching between Light and Dark. You confirm each switch.",
        pt: "Quando a luz ao redor do seu Mac muda, sugere alternar entre Claro e Escuro. Você confirma cada troca."
    )
    static let ambientThresholdDark = LocalizedText(en: "Suggest Dark below", pt: "Sugerir Escuro abaixo de")
    static let ambientThresholdLight = LocalizedText(en: "Suggest Light above", pt: "Sugerir Claro acima de")
    static let ambientDwellLabel = LocalizedText(en: "Hold for (s)", pt: "Aguardar (s)")
    static let ambientCurrentLight = LocalizedText(en: "Current light", pt: "Luz atual")
    static let ambientNoSensor = LocalizedText(
        en: "No ambient light sensor on this Mac.",
        pt: "Sem sensor de luz ambiente neste Mac."
    )

    // Shared
    static let unavailable = LocalizedText(en: "Unavailable", pt: "Indisponível")
}
