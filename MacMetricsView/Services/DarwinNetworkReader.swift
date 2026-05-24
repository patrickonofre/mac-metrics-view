import Darwin
import Foundation

final class DarwinNetworkReader: NetworkReading {
    func readSnapshot() -> NetworkCounterSnapshot? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var foundEligibleInterface = false

        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let data = interface.pointee.ifa_data
            else {
                continue
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            receivedBytes += UInt64(interfaceData.ifi_ibytes)
            sentBytes += UInt64(interfaceData.ifi_obytes)
            foundEligibleInterface = true
        }

        guard foundEligibleInterface else { return nil }

        return NetworkCounterSnapshot(
            receivedBytes: receivedBytes,
            sentBytes: sentBytes
        )
    }
}
