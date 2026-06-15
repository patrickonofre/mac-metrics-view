import XCTest
@testable import MacMetricsView

final class SMCTemperatureReaderTests: XCTestCase {
    private struct FakeSMCKeySource: SMCKeySource {
        let readings: [TemperatureSensorReading]
        func readKeys() -> [TemperatureSensorReading] { readings }
    }

    private func reader(
        _ readings: [TemperatureSensorReading],
        state: TemperatureState = .normal
    ) -> SMCTemperatureReader {
        SMCTemperatureReader(source: FakeSMCKeySource(readings: readings), thermalState: { state })
    }

    func testAveragesPlausibleCPUKeys() {
        let sample = reader([
            TemperatureSensorReading(name: "TC0P", celsius: 50),
            TemperatureSensorReading(name: "TC0D", celsius: 60)
        ]).readSample()

        XCTAssertEqual(sample?.celsius, 55)
        XCTAssertEqual(sample?.state, .normal)
    }

    func testSelectsOnlyCPUKeysAndIgnoresOtherDomains() {
        // GPU (TG0P) and battery (TB0T) keys must not contribute to the CPU average.
        let sample = reader([
            TemperatureSensorReading(name: "TC0P", celsius: 40),
            TemperatureSensorReading(name: "TG0P", celsius: 90),
            TemperatureSensorReading(name: "TB0T", celsius: 30),
            TemperatureSensorReading(name: "TCXC", celsius: 50)
        ]).readSample()

        XCTAssertEqual(sample?.celsius, 45)
    }

    func testClampsDropImplausibleAndNonPositiveValues() {
        let sample = reader([
            TemperatureSensorReading(name: "TC0P", celsius: 55),
            TemperatureSensorReading(name: "TC0D", celsius: 0),       // non-positive artifact
            TemperatureSensorReading(name: "TC0E", celsius: 999),     // out of plausible range
            TemperatureSensorReading(name: "TC0F", celsius: .nan)     // NaN
        ]).readSample()

        XCTAssertEqual(sample?.celsius, 55)
    }

    func testNoUsableKeysYieldsNilCelsiusButKeepsState() {
        let sample = reader([
            TemperatureSensorReading(name: "TG0P", celsius: 70)
        ], state: .warm).readSample()

        XCTAssertNil(sample?.celsius)
        XCTAssertEqual(sample?.state, .warm)
    }

    func testEmptySourceYieldsStateOnlySample() {
        let sample = reader([], state: .hot).readSample()

        XCTAssertNil(sample?.celsius)
        XCTAssertEqual(sample?.state, .hot)
    }

    // MARK: - Decoding

    func testDecodeSP78FixedPoint() {
        var bytes = zeroBytes()
        bytes.0 = 50            // whole degrees
        bytes.1 = 128           // 0.5 fraction (128/256)
        let value = AppleSMCKeySource.decode(type: AppleSMCKeySource.fourCharCode("sp78")!, size: 2, bytes: bytes)
        XCTAssertEqual(value ?? 0, 50.5, accuracy: 0.001)
    }

    func testDecodeFloatLittleEndian() {
        var bytes = zeroBytes()
        let raw = Float(42.5).bitPattern
        bytes.0 = UInt8(raw & 0xFF)
        bytes.1 = UInt8((raw >> 8) & 0xFF)
        bytes.2 = UInt8((raw >> 16) & 0xFF)
        bytes.3 = UInt8((raw >> 24) & 0xFF)
        let value = AppleSMCKeySource.decode(type: AppleSMCKeySource.fourCharCode("flt ")!, size: 4, bytes: bytes)
        XCTAssertEqual(value ?? 0, 42.5, accuracy: 0.001)
    }

    func testDecodeUnknownTypeReturnsNil() {
        XCTAssertNil(AppleSMCKeySource.decode(type: AppleSMCKeySource.fourCharCode("ui8 ")!, size: 1, bytes: zeroBytes()))
    }

    func testDecodeRejectsUndersizedBuffers() {
        XCTAssertNil(AppleSMCKeySource.decode(type: AppleSMCKeySource.fourCharCode("sp78")!, size: 1, bytes: zeroBytes()))
        XCTAssertNil(AppleSMCKeySource.decode(type: AppleSMCKeySource.fourCharCode("flt ")!, size: 3, bytes: zeroBytes()))
    }

    func testFourCharCodePacksBigEndianASCII() {
        // "TC0P" → 0x54 43 30 50
        XCTAssertEqual(AppleSMCKeySource.fourCharCode("TC0P"), 0x5443_3050)
        XCTAssertNil(AppleSMCKeySource.fourCharCode("TC0"))      // too short
        XCTAssertNil(AppleSMCKeySource.fourCharCode("TC0PX"))    // too long
    }

    private func zeroBytes() -> SMCBytes {
        (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }
}
