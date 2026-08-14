import Foundation

struct Environment: Sendable {
    var date: @Sendable () -> Date = Date.init
    var uuid: @Sendable () -> UUID = UUID.init
    var visitorToken: @Sendable () -> UUID = visitorTokenProvider
    /// `UserDefaults` is documented as thread-safe, but carries no `Sendable` conformance
    nonisolated(unsafe) var defaults: UserDefaults = .standard
    var didBecomeActiveNotification: Notification.Name? = ApplicationLifecycle.didBecomeActiveNotification
    var notificationCenter: NotificationCenter = .default
}

#if DEBUG
/// Substituted by the test suite before any tracking begins; never mutated once concurrent work is under way.
nonisolated(unsafe) var Current: Environment = .init()
#else
let Current: Environment = .init()
#endif

#if canImport(WatchKit)
import WatchKit

let visitorTokenProvider: @Sendable () -> UUID = {
    WKInterfaceDevice.current().identifierForVendor ?? Current.uuid()
}
#elseif canImport(UIKit)
import UIKit

let visitorTokenProvider: @Sendable () -> UUID = {
    UIDevice.current.identifierForVendor ?? Current.uuid()
}
#elseif canImport(AppKit)
import AppKit

let visitorTokenProvider: @Sendable () -> UUID = {
    let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
    let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict)

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
#endif
