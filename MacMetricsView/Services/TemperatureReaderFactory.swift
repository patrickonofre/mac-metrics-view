import Foundation

/// Selects the temperature reader for the current hardware at runtime. Apple Silicon
/// reads numeric Celsius via IOKit; Intel reads it from the SMC (`SMCTemperatureReader`).
/// Numeric absence is handled inside each reader (`celsius = nil`), so the state-only
/// fallback never regresses today's UI even if a given Mac exposes no usable keys.
enum TemperatureReaderFactory {
    static func makeDefault() -> TemperatureReading {
        #if arch(arm64)
        return IOKitTemperatureReader()
        #else
        return SMCTemperatureReader()
        #endif
    }
}
