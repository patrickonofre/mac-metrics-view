import XCTest
@testable import MacMetricsView

final class IOKitAmbientLightReaderTests: XCTestCase {
    private struct FakeSource: AmbientLightSensorSource {
        let level: Double?
        func readLevel() -> Double? { level }
    }

    func testReadsLevelIntoSample() {
        let reader = IOKitAmbientLightReader(source: FakeSource(level: 261))

        XCTAssertEqual(reader.readSample()?.lux, 261)
    }

    func testZeroLevelIsValid() {
        let reader = IOKitAmbientLightReader(source: FakeSource(level: 0))

        XCTAssertEqual(reader.readSample()?.lux, 0)
    }

    func testNilLevelYieldsNoSample() {
        let reader = IOKitAmbientLightReader(source: FakeSource(level: nil))

        XCTAssertNil(reader.readSample())
    }

    func testNegativeLevelYieldsNoSample() {
        let reader = IOKitAmbientLightReader(source: FakeSource(level: -1))

        XCTAssertNil(reader.readSample())
    }

    func testNaNLevelYieldsNoSample() {
        let reader = IOKitAmbientLightReader(source: FakeSource(level: .nan))

        XCTAssertNil(reader.readSample())
    }
}
