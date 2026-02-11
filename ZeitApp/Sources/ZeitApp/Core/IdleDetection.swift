import Foundation
import IOKit

/// Detects system idle time using IOKit
enum IdleDetection {
    /// Get the system idle time in seconds
    /// Returns nil if unable to determine
    static func getIdleTimeSeconds() -> Double? {
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            return nil
        }

        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?

        guard IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedDict,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else {
            return nil
        }

        guard let dict = unmanagedDict?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // HIDIdleTime is in nanoseconds
        guard let idleTimeNS = dict["HIDIdleTime"] as? Int64 else {
            return nil
        }

        // Convert nanoseconds to seconds
        return Double(idleTimeNS) / 1_000_000_000.0
    }

    /// Check if the system is considered idle
    /// - Parameter threshold: Idle threshold in seconds (default: 300 = 5 minutes)
    static func isSystemIdle(threshold: Double = 300) -> Bool {
        guard let idleTime = getIdleTimeSeconds() else {
            return false
        }
        return idleTime > threshold
    }

    /// Get idle threshold from environment variable or default
    static func getIdleThreshold() -> Double {
        if let envValue = ProcessInfo.processInfo.environment["IDLE_THRESHOLD_SECONDS"],
           let threshold = Double(envValue)
        {
            return threshold
        }
        return 300  // Default: 5 minutes
    }
}
