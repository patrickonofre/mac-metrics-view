import Foundation

/// Reads the Apple Silicon ambient light sensor through the private
/// `IOHIDEventSystemClient` API — the same mechanism as `IOHIDTemperatureSensorSource`,
/// with the matching narrowed to the ALS service and the ALS event type. Symbols are
/// resolved at runtime via `dlsym` (no private header linked). When a symbol or the
/// client is unavailable, `readLevel()` returns `nil` and the reader produces no
/// sample. Local-only, no entitlement, no privileges.
///
/// Empirically confirmed on the reference Mac: the ALS service matches
/// `PrimaryUsagePage 0xff00` / `PrimaryUsage 0x4` (temperature uses usage `5`), event
/// type `12`, and the usable "Level" value is at field offset `+0`.
final class IOHIDAmbientLightSource: AmbientLightSensorSource {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias ClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias ClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias ServiceCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias EventGetFloatValue = @convention(c) (AnyObject, Int64) -> Double

    private struct Symbols {
        let create: ClientCreate
        let setMatching: ClientSetMatching
        let copyServices: ClientCopyServices
        let copyEvent: ServiceCopyEvent
        let floatValue: EventGetFloatValue
    }

    // kIOHIDEventTypeAmbientLightSensor = 12; the float field is the event type shifted
    // into the field base (type << 16), offset +0 = the "Level" channel.
    private static let ambientLightEventType: Int64 = 12
    private static let primaryUsagePage = 0xff00
    private static let primaryUsage = 0x4

    private lazy var symbols: Symbols? = Self.resolveSymbols()
    private lazy var client: AnyObject? = makeClient()

    /// Enumerated ALS services, resolved once and reused (OPT-13; same rationale as the
    /// temperature source). `nil` = not yet enumerated; an empty enumeration is never cached;
    /// a cache that stops emitting is dropped so the next read re-enumerates.
    private var cachedServices: [AnyObject]?

    func readLevel() -> Double? {
        guard let symbols, let client else { return nil }

        let services: [AnyObject]
        if let cached = cachedServices {
            services = cached
        } else {
            guard let enumerated = symbols.copyServices(client)?.takeRetainedValue() as? [AnyObject],
                  !enumerated.isEmpty else { return nil }
            cachedServices = enumerated
            services = enumerated
        }

        let field = Self.ambientLightEventType << 16
        for service in services {
            guard let event = symbols.copyEvent(service, Self.ambientLightEventType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            return symbols.floatValue(event, field)
        }

        // Nothing emitted → the cached services are stale; drop so the next read re-enumerates.
        cachedServices = nil
        return nil
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
            let floatValue = symbol("IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        else {
            return nil
        }
        return Symbols(
            create: create,
            setMatching: setMatching,
            copyServices: copyServices,
            copyEvent: copyEvent,
            floatValue: floatValue
        )
    }
}
