import Foundation

/// Apple Silicon ambient-light reader: reads the IOHID "Level" channel and wraps it
/// in an `AmbientLightSample`. Returns `nil` (never a failure) when no ALS service
/// responds or the value is implausible, so the feature self-hides on hardware
/// without a sensor (NFR-1). Mirrors `IOKitTemperatureReader`'s clamp/`nil`-absence
/// shape.
struct IOKitAmbientLightReader: AmbientLightReading {
    private let source: AmbientLightSensorSource

    init(source: AmbientLightSensorSource = IOHIDAmbientLightSource()) {
        self.source = source
    }

    func readSample() -> AmbientLightSample? {
        // A finite, non-negative level is the only plausibility gate: 0 = pitch black is
        // valid, NaN / negative are calibration artifacts and yield no sample.
        guard let level = source.readLevel(), level.isFinite, level >= 0 else { return nil }
        return AmbientLightSample(lux: level)
    }
}
