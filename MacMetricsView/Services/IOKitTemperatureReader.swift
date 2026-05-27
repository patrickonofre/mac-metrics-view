import Foundation

/// Apple Silicon temperature reader: derives a representative CPU/SoC temperature by
/// averaging the die / core-cluster sensors (names containing `tdie` or
/// `MTR Temp Sensor`) after a plausibility clamp, and always reports the current
/// thermal state. Returns `celsius = nil` (never a failure) when no usable sensor
/// exists, so the UI falls back to the state label without regression.
struct IOKitTemperatureReader: TemperatureReading {
    private static let sensorNameNeedles = ["tdie", "MTR Temp Sensor"]

    private let source: TemperatureSensorSource
    private let thermalState: () -> TemperatureState

    init(
        source: TemperatureSensorSource = IOHIDTemperatureSensorSource(),
        thermalState: @escaping () -> TemperatureState = { ProcessInfo.processInfo.thermalState.temperatureState }
    ) {
        self.source = source
        self.thermalState = thermalState
    }

    func readSample() -> TemperatureSample? {
        let state = thermalState()

        let plausible = source.readSensors()
            .filter { reading in
                Self.sensorNameNeedles.contains { reading.name.contains($0) }
            }
            .map(\.celsius)
            // Drop NaN, non-positive offsets/calibration artifacts, and anything outside
            // the plausible range, so a bogus reading never reaches TemperatureSample.
            .filter { $0.isFinite && $0 > 0 && TemperatureSample.plausibleCelsiusRange.contains($0) }

        let celsius = plausible.isEmpty ? nil : plausible.reduce(0, +) / Double(plausible.count)
        return TemperatureSample(celsius: celsius, state: state)
    }
}
