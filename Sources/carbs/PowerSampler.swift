import Foundation
import IOKit

struct PowerSample {
    let watts: Double
    let source: String // "battery" | "charging" | "plugged"
}

enum PowerSampler {
    /// Instantaneous watts at the battery rail via IOKit (no sudo, no powermetrics).
    /// Known limitation: when plugged in with a full battery, InstantAmperage ≈ 0
    /// and draw from the adapter is undercounted. Documented in PLAN.md §8.
    static func currentWatts() -> PowerSample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        guard let voltageMV = (dict["Voltage"] as? NSNumber)?.doubleValue,
              let amperageMA = (dict["InstantAmperage"] as? NSNumber)?.doubleValue else { return nil }

        let watts = abs(voltageMV * amperageMA) / 1_000_000.0
        let external = (dict["ExternalConnected"] as? Bool) ?? false
        let charging = (dict["IsCharging"] as? Bool) ?? false
        let source = external ? (charging ? "charging" : "plugged") : "battery"
        return PowerSample(watts: watts, source: source)
    }
}
