import Foundation
import IOKit.ps

/// Where the machine draws its power, for `tracking.skip_on_battery`.
enum PowerSource {
    /// Whether the machine is running on battery right now.
    ///
    /// A desktop, or a laptop that cannot be asked, reads as not on battery:
    /// the gate exists to save a battery, and failing to read one is no reason
    /// to stop tracking.
    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue()
        else {
            return false
        }

        return (type as String) == kIOPSBatteryPowerValue
    }
}
