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
    static let ramMenuBarMetric = LocalizedText(en: "Menu bar", pt: "Barra")
    static let ramMetricAppMemoryShort = LocalizedText(en: "App", pt: "Apps")
    static let ramMetricPressureShort = LocalizedText(en: "Pressure", pt: "Pressão")
    static let ramMenuBarMetricHelpTitle = LocalizedText(
        en: "Which RAM value shows in the menu bar",
        pt: "Qual valor de RAM aparece na barra"
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

    // Visibility / display controls
    static let displayLabel = LocalizedText(en: "Display", pt: "Exibição")
    static let displayIcon = LocalizedText(en: "Icon", pt: "Ícone")
    static let displayText = LocalizedText(en: "Label", pt: "Rótulo")

    // Empty state
    static let noMetricsTitle = LocalizedText(en: "No Metrics Visible", pt: "Nenhuma métrica visível")
    static let noMetricsHint = LocalizedText(
        en: "Turn on CPU, RAM, Network, or Temperature to show live values.",
        pt: "Ative CPU, RAM, Rede ou Temperatura para ver valores ao vivo."
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

    // Shared
    static let unavailable = LocalizedText(en: "Unavailable", pt: "Indisponível")
}
