import Foundation

/// A single raw temperature sensor reading: a sensor's product name and its value in
/// degrees Celsius. Plausibility filtering and selection happen in the reader, not here.
struct TemperatureSensorReading: Equatable {
    let name: String
    let celsius: Double
}

/// Injectable seam for enumerating hardware temperature sensors. The real
/// implementation reads `IOHIDEventSystemClient` via `dlsym`; tests inject a fake so
/// the reader's selection/clamp/averaging logic runs without hardware or private API.
protocol TemperatureSensorSource {
    func readSensors() -> [TemperatureSensorReading]
}

/// Reads Apple Silicon temperature sensors through the private
/// `IOHIDEventSystemClient` API. Symbols are resolved at runtime via `dlsym` — no
/// private header is linked into the app. When a symbol or the client is unavailable
/// (e.g. a future macOS removes the API), `readSensors()` returns an empty array and
/// the reader falls back to thermal state. Local-only, no entitlement, no privileges.
final class IOHIDTemperatureSensorSource: TemperatureSensorSource {
    // IOHIDEventSystemClient/Service/Event handles are CoreFoundation objects, so the
    // opaque references are modeled as AnyObject. "Create"/"Copy" return +1, hence
    // Unmanaged + takeRetainedValue.
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias ClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias ClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias ServiceCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias ServiceCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias EventGetFloatValue = @convention(c) (AnyObject, Int64) -> Double

    private struct Symbols {
        let create: ClientCreate
        let setMatching: ClientSetMatching
        let copyServices: ClientCopyServices
        let copyEvent: ServiceCopyEvent
        let copyProperty: ServiceCopyProperty
        let floatValue: EventGetFloatValue
    }

    // kIOHIDEventTypeTemperature = 15; the float field is the event type shifted into
    // the field base (type << 16). Matching keys narrow services to Apple's
    // temperature sensors (PrimaryUsagePage 0xff00 / PrimaryUsage 0x0005).
    private static let temperatureEventType: Int64 = 15
    private static let primaryUsagePage = 0xff00
    private static let primaryUsage = 0x0005

    private lazy var symbols: Symbols? = Self.resolveSymbols()
    private lazy var client: AnyObject? = makeClient()

    func readSensors() -> [TemperatureSensorReading] {
        guard let symbols, let client else { return [] }
        guard let services = symbols.copyServices(client)?.takeRetainedValue() as NSArray? else { return [] }

        let field = Self.temperatureEventType << 16
        var readings: [TemperatureSensorReading] = []
        for case let service as AnyObject in services {
            guard let event = symbols.copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let celsius = symbols.floatValue(event, field)
            let name = symbols.copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            readings.append(TemperatureSensorReading(name: name, celsius: celsius))
        }
        return readings
    }

    private func makeClient() -> AnyObject? {
        guard let symbols, let client = symbols.create(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        let matching: [String: Int] = [
            "PrimaryUsagePage": Self.primaryUsagePage,
            "PrimaryUsage": Self.primaryUsage
        ]
        symbols.setMatching(client, matching as CFDictionary)
        return client
    }

    private static func resolveSymbols() -> Symbols? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return nil
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard
            let create = symbol("IOHIDEventSystemClientCreate", as: ClientCreate.self),
            let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self),
            let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self),
            let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self),
            let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self),
            let floatValue = symbol("IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        else {
            return nil
        }
        return Symbols(
            create: create,
            setMatching: setMatching,
            copyServices: copyServices,
            copyEvent: copyEvent,
            copyProperty: copyProperty,
            floatValue: floatValue
        )
    }
}
