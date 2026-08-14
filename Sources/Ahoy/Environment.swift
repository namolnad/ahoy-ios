import Foundation

struct Environment: Sendable {
    var date: @Sendable () -> Date = Date.init
    var uuid: @Sendable () -> UUID = UUID.init
    var visitorToken: @Sendable () -> UUID = visitorTokenProvider
    /// `UserDefaults` is documented as thread-safe, but carries no `Sendable` conformance
    nonisolated(unsafe) var defaults: UserDefaults = .standard
    /// Resolved on use rather than captured at initialization, so that it is read after `ApplicationLifecycle.prime()`
    var didBecomeActiveNotification: @Sendable () -> Notification.Name? = { ApplicationLifecycle.didBecomeActiveNotification }
    var notificationCenter: NotificationCenter = .default
}

#if DEBUG
/// Substituted by the test suite before any tracking begins; never mutated once concurrent work is under way.
nonisolated(unsafe) var Current: Environment = .init()
#else
let Current: Environment = .init()
#endif

/// Reads the vendor identifier while the caller may still be on the main actor. Visitor tokens are minted on
/// Ahoy's executor, where the platform will not hand it over, so it has to be resolved ahead of that.
/// A no-op on platforms with no vendor identifier to read.
func primeVendorIdentifier() {
    #if canImport(WatchKit) || canImport(UIKit)
    _ = vendorIdentifier.resolve()
    #endif
}

#if canImport(WatchKit)
import WatchKit

let vendorIdentifier: MainActorCache<UUID> = .init { WKInterfaceDevice.current().identifierForVendor }

let visitorTokenProvider: @Sendable () -> UUID = {
    vendorIdentifier.resolve() ?? Current.uuid()
}
#elseif canImport(UIKit)
import UIKit

let vendorIdentifier: MainActorCache<UUID> = .init { UIDevice.current.identifierForVendor }

let visitorTokenProvider: @Sendable () -> UUID = {
    vendorIdentifier.resolve() ?? Current.uuid()
}
#elseif canImport(AppKit)
import AppKit

let visitorTokenProvider: @Sendable () -> UUID = {
    let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
    // `kIOMainPortDefault` needs macOS 12 and its predecessor `kIOMasterPortDefault` is deprecated; both are
    // the null port, which `IOServiceGetMatchingService` reads as "the default I/O Kit port"
    let platformExpert = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), matchingDict)

    defer { IOObjectRelease(platformExpert) }

    guard
        platformExpert != 0,
        let uuidString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault, 0
        ).takeRetainedValue() as? String,
        let uuid = UUID(uuidString: uuidString)
    else { return Current.uuid() }

    return uuid
}
#else
let visitorTokenProvider: @Sendable () -> UUID = {
    Current.uuid()
}
#endif
