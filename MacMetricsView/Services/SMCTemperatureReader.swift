import Foundation
import IOKit

/// Injectable seam for reading Apple SMC temperature keys. The real implementation
/// talks to the `AppleSMC` IOService; tests inject a fake so the reader's
/// selection/clamp/averaging logic runs without Intel hardware or the SMC. Mirrors
/// `TemperatureSensorSource` (Apple Silicon) so both readers share one shape.
protocol SMCKeySource {
    /// One reading per SMC key that decoded successfully. `name` is the four-character
    /// key (e.g. `TC0P`); `celsius` is the decoded value. No filtering here — the
    /// reader selects and clamps.
    func readKeys() -> [TemperatureSensorReading]
}

/// Intel temperature reader: averages the plausible CPU SMC keys (proximity / die /
/// PECI) after a range clamp, and always reports the current thermal state. Returns
/// `celsius = nil` (never a failure) when no usable key exists, so the UI falls back to
/// the state label without regression — identical contract to `IOKitTemperatureReader`.
struct SMCTemperatureReader: TemperatureReading {
    /// CPU-related key prefixes worth averaging: per-core proximity/die (`TC0…`),
    /// package PECI (`TCXC`), and die-average (`TCAD`/`TCMX`). GPU (`TG…`), battery
    /// (`TB…`), and other domains are excluded.
    private static let keyNeedles = ["TC0", "TC1", "TC2", "TC3", "TCXC", "TCAD", "TCMX"]

    private let source: SMCKeySource
    private let thermalState: () -> TemperatureState

    init(
        source: SMCKeySource = AppleSMCKeySource(),
        thermalState: @escaping () -> TemperatureState = { ProcessInfo.processInfo.thermalState.temperatureState }
    ) {
        self.source = source
        self.thermalState = thermalState
    }

    func readSample() -> TemperatureSample? {
        let state = thermalState()

        let plausible = source.readKeys()
            .filter { reading in
                Self.keyNeedles.contains { reading.name.hasPrefix($0) }
            }
            .map(\.celsius)
            // Drop NaN, non-positive calibration artifacts, and out-of-range values so a
            // bogus SMC decode never reaches TemperatureSample.
            .filter { $0.isFinite && $0 > 0 && TemperatureSample.plausibleCelsiusRange.contains($0) }

        let celsius = plausible.isEmpty ? nil : plausible.reduce(0, +) / Double(plausible.count)
        return TemperatureSample(celsius: celsius, state: state)
    }
}

/// Real `SMCKeySource`: reads CPU temperature keys from the `AppleSMC` IOService via
/// `IOConnectCallStructMethod`. Every step is guarded — a missing service, a closed
/// connection, an unknown key, or an unsupported data type yields no reading rather
/// than a crash, so the reader degrades to the state-only fallback. Local-only, no
/// entitlement, no elevated privileges. Only used on Intel (the factory picks the
/// IOKit reader on Apple Silicon), but compiles on every arch.
final class AppleSMCKeySource: SMCKeySource {
    /// Candidate CPU keys, tried in order; whichever decode are returned. Different
    /// Intel models expose different subsets, so the reader averages what is present.
    private static let candidateKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TCXC", "TCAD"]

    func readKeys() -> [TemperatureSensorReading] {
        guard let connection = openConnection() else { return [] }
        defer { IOServiceClose(connection) }

        return Self.candidateKeys.compactMap { key in
            guard let celsius = readKey(key, connection: connection) else { return nil }
            return TemperatureSensorReading(name: key, celsius: celsius)
        }
    }

    private func openConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { return nil }
        return connection
    }

    /// Reads one key: first its metadata (size + type) via `kSMCGetKeyInfo`, then its
    /// bytes via `kSMCReadKey`, then decodes the SMC fixed-point / float type.
    private func readKey(_ key: String, connection: io_connect_t) -> Double? {
        guard let keyCode = Self.fourCharCode(key) else { return nil }

        var info = SMCParamStruct()
        info.key = keyCode
        info.data8 = Self.kSMCGetKeyInfo
        guard let infoResult = call(connection, input: info),
              infoResult.result == Self.kSMCSuccess
        else {
            return nil
        }

        var read = SMCParamStruct()
        read.key = keyCode
        read.keyInfo.dataSize = infoResult.keyInfo.dataSize
        read.keyInfo.dataType = infoResult.keyInfo.dataType
        read.data8 = Self.kSMCReadKey
        guard let readResult = call(connection, input: read),
              readResult.result == Self.kSMCSuccess
        else {
            return nil
        }

        return Self.decode(
            type: infoResult.keyInfo.dataType,
            size: infoResult.keyInfo.dataSize,
            bytes: readResult.bytes
        )
    }

    private func call(_ connection: io_connect_t, input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            Self.kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }
        return output
    }

    /// Decodes the two temperature encodings SMC uses in practice: `sp78` (signed
    /// 8.8 fixed-point, 2 bytes) and `flt ` (little-endian Float, 4 bytes). Any other
    /// type returns nil so the key is skipped rather than misread.
    static func decode(type: UInt32, size: UInt32, bytes: SMCBytes) -> Double? {
        let raw = withUnsafeBytes(of: bytes) { Array($0) }

        switch type {
        case fourCharCode("sp78"):
            guard size >= 2 else { return nil }
            let whole = Double(Int8(bitPattern: raw[0]))
            let fraction = Double(raw[1]) / 256.0
            return whole + fraction
        case fourCharCode("flt "):
            guard size >= 4 else { return nil }
            let bits = UInt32(raw[0]) | (UInt32(raw[1]) << 8) | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    /// Packs a four-character key (e.g. `TC0P`) into the big-endian `UInt32` the SMC
    /// expects. Returns nil for non-four-character or non-ASCII keys.
    static func fourCharCode(_ string: String) -> UInt32? {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 4, scalars.allSatisfy({ $0.isASCII }) else { return nil }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1.value) }
    }

    // SMC selector + result constants (stable across macOS).
    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyInfo: UInt8 = 9
    private static let kSMCSuccess: UInt8 = 0
}

/// 32-byte SMC value buffer. Modeled as a fixed-size tuple so the `SMCParamStruct`
/// layout matches the kernel's expectation for `IOConnectCallStructMethod`.
typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

/// Mirror of the kernel's `SMCKeyData_t`. Field order and sizes must match exactly or
/// `IOConnectCallStructMethod` reads garbage; this is the long-standing public layout.
struct SMCParamStruct {
    struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Vers()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
