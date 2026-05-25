import XCTest
@testable import MacMetricsView

@MainActor
final class TemperatureSamplerTests: XCTestCase {
    private final class FakeReader: TemperatureReading {
        var state: TemperatureState = .normal
        func readSample() -> TemperatureSample? {
            TemperatureSample(celsius: nil, state: state)
        }
    }

    private final class SpyDelegate: TemperatureSamplerDelegate {
        var samples: [TemperatureSample] = []
        func temperatureSampler(_ sampler: TemperatureSampler, didProduce sample: TemperatureSample) {
            samples.append(sample)
        }
    }

    func testEmitsInitialSampleOnStart() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(reader: reader, notificationCenter: center, deliveryQueue: nil)
        sampler.delegate = delegate

        sampler.start()

        XCTAssertEqual(delegate.samples.map(\.state), [.normal])
    }

    func testSamplesAgainOnThermalStateChange() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(reader: reader, notificationCenter: center, deliveryQueue: nil)
        sampler.delegate = delegate

        sampler.start()
        reader.state = .hot
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        XCTAssertEqual(delegate.samples.map(\.state), [.normal, .hot])
    }

    func testStopUnsubscribesFromNotifications() {
        let reader = FakeReader()
        let center = NotificationCenter()
        let delegate = SpyDelegate()
        let sampler = TemperatureSampler(reader: reader, notificationCenter: center, deliveryQueue: nil)
        sampler.delegate = delegate

        sampler.start()
        sampler.stop()
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        XCTAssertEqual(delegate.samples.map(\.state), [.normal])
    }
}
