import XCTest
@testable import MacMetricsView

final class IOKitTemperatureReaderTests: XCTestCase {
    private struct FakeSource: TemperatureSensorSource {
        let sensors: [TemperatureSensorReading]
        func readSensors() -> [TemperatureSensorReading] { sensors }
    }

    private func makeReader(
        _ sensors: [TemperatureSensorReading],
        state: TemperatureState = .normal
    ) -> IOKitTemperatureReader {
        IOKitTemperatureReader(source: FakeSource(sensors: sensors), thermalState: { state })
    }

    func testAveragesOnlyRelevantInRangeSensors() {
        let reader = makeReader([
            TemperatureSensorReading(name: "PMU tdie1", celsius: 40),
            TemperatureSensorReading(name: "SOC MTR Temp Sensor3", celsius: 44),
            TemperatureSensorReading(name: "GPU MTR Temp Sensor1", celsius: 200), // out of range, dropped
            TemperatureSensorReading(name: "gas gauge battery", celsius: 30),     // wrong name, dropped
            TemperatureSensorReading(name: "PMU tdev1", celsius: -21)             // negative, dropped
        ])

        let sample = reader.readSample()

        XCTAssertEqual(sample?.celsius, 42) // (40 + 44) / 2
        XCTAssertEqual(sample?.state, .normal)
    }

    func testOnlyOutOfRangeRelevantSensorsYieldsNilCelsius() {
        let reader = makeReader([
            TemperatureSensorReading(name: "PMU tdev1", celsius: -21),
            TemperatureSensorReading(name: "PMU tdie2", celsius: .nan),
            TemperatureSensorReading(name: "SOC MTR Temp Sensor1", celsius: 999)
        ], state: .hot)

        let sample = reader.readSample()

        XCTAssertNil(sample?.celsius)
        XCTAssertEqual(sample?.state, .hot)
    }

    func testNoSensorsYieldsNilCelsius() {
        let reader = makeReader([], state: .warm)

        let sample = reader.readSample()

        XCTAssertNil(sample?.celsius)
        XCTAssertEqual(sample?.state, .warm)
    }
}
